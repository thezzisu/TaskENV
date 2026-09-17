//! Temporary HTTP/WebSocket forwarding through the existing sandbox data plane.

use std::net::Ipv4Addr;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{bail, ensure, Context, Result};
use axum::body::Body;
use axum::extract::{Request, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Router;
use envd::process::{process_event, StartResponse};
use futures::StreamExt;
use hyper_util::rt::TokioIo;
use serde::Deserialize;
use tokio::net::TcpListener;

use crate::client::Client;
use crate::grpc::{build_start_request, StartOpts, Transport};

const DESKD_PORT: u16 = 6900;

#[derive(Deserialize)]
struct DesktopConnection {
    version: u32,
    port: u16,
    authentication: DesktopCredentials,
}

#[derive(Clone, Deserialize)]
struct DesktopCredentials {
    scheme: String,
    username: String,
    password: String,
}

impl DesktopConnection {
    async fn load(transport: &Transport) -> Result<Self> {
        tokio::time::timeout(Duration::from_secs(10), async {
            let request = build_start_request(StartOpts {
                // Old snapshots pin the tools release from before deskd moved
                // onto the drive. Keep them attachable without modifying it.
                cmd: "/bin/sh",
                args: vec!["-c".to_string(), "if [ -x /agentenv/deskd ]; then exec /agentenv/deskd connect-info; else exec /usr/bin/deskd connect-info; fi".to_string()],
                envs: Default::default(),
                pty: None,
                stdin: false,
            });
            let mut stream = transport.server_stream::<_, StartResponse>("Start", request).await
                .map_err(|_| anyhow::anyhow!("cannot invoke deskd connect-info; upgrade deskd to 0.1.1 or later and check the desktop"))?;
            let mut data = Vec::new();
            while let Some(message) = stream.next().await {
                // Command output and RPC errors may contain connection secrets.
                // Collect stdout privately; never print stderr or exit details.
                let message = message.map_err(|_| anyhow::anyhow!("deskd connection request failed"))?;
                match message.event.and_then(|event| event.event) {
                    Some(process_event::Event::Data(event)) => {
                        if let Some(process_event::data_event::Output::Stdout(chunk)) = event.output {
                            ensure!(data.len() + chunk.len() <= 16 * 1024, "deskd connection response is too large");
                            data.extend_from_slice(&chunk);
                        }
                    }
                    Some(process_event::Event::End(event)) => {
                        ensure!(event.exited && event.exit_code == 0,
                            "deskd connect-info failed; ensure deskd 0.1.1 or later is installed and deskd check succeeds");
                        return Self::parse(&data);
                    }
                    _ => {}
                }
            }
            bail!("deskd connection request ended without an exit event")
        })
        .await
        .context("timed out requesting desktop connection information")?
    }

    fn parse(data: &[u8]) -> Result<Self> {
        // Deserialization errors can quote input values; never print the response.
        let connection: Self = serde_json::from_slice(data)
            .map_err(|_| anyhow::anyhow!("invalid deskd connection response"))?;
        ensure!(
            connection.version == 1,
            "unsupported deskd connection protocol"
        );
        ensure!(connection.port != 0, "invalid deskd connection port");
        let credentials = &connection.authentication;
        ensure!(
            credentials.scheme == "basic",
            "unsupported deskd authentication scheme"
        );
        ensure!(
            !credentials.username.is_empty()
                && !credentials.username.contains(':')
                && !credentials.username.chars().any(char::is_control)
                && !credentials.password.is_empty()
                && !credentials.password.chars().any(char::is_control),
            "invalid deskd connection response"
        );
        Ok(connection)
    }
}

#[derive(Clone)]
struct Forward {
    http: reqwest::Client,
    upstream: String,
    authority: String,
    routing: HeaderMap,
    credentials: Option<DesktopCredentials>,
}

pub(super) async fn attach(
    client: Client,
    sandbox_id: String,
    port: u16,
    open: bool,
) -> Result<()> {
    let sandbox = client.connect_sandbox(&sandbox_id, super::DEFAULT_TIMEOUT_SECS)?;
    // deskd owns its endpoint and authentication. envd is only the existing
    // authenticated command transport, with no desktop-specific API or paths.
    let connection = if port == DESKD_PORT {
        Some(
            DesktopConnection::load(
                &client.transport(&sandbox_id, sandbox.envd_access_token.as_deref())?,
            )
            .await?,
        )
    } else {
        None
    };
    let port = connection.as_ref().map_or(port, |info| info.port);
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?;
    let authority = listener.local_addr()?.to_string();
    let mut forward = Forward::new(
        client.base_url(),
        &sandbox_id,
        port,
        sandbox.traffic_access_token.as_deref(),
        authority.clone(),
    )?;
    forward.credentials = connection.map(|info| info.authentication);
    let url = format!("http://{authority}/");
    println!("Desktop: {url}");
    eprintln!("Forwarding sandbox port {port}. Ctrl-C disconnects; the desktop keeps running.");
    if open {
        open_browser(&url);
    }
    let router = Router::new().fallback(proxy).with_state(Arc::new(forward));
    let keepalive = async {
        let mut tick = tokio::time::interval(Duration::from_secs(60));
        tick.tick().await;
        loop {
            tick.tick().await;
            let client = client.clone();
            let sandbox_id = sandbox_id.clone();
            let result = tokio::task::spawn_blocking(move || {
                client.refresh_sandbox(&sandbox_id, Some(super::DEFAULT_TIMEOUT_SECS))
            })
            .await?;
            if let Err(error) = result {
                break Err::<(), _>(error.context("desktop sandbox is no longer available"));
            }
        }
    };
    tokio::select! {
        result = axum::serve(listener, router) => result.context("desktop forward failed"),
        result = tokio::signal::ctrl_c() => result.context("waiting for Ctrl-C"),
        result = keepalive => result,
    }
}

impl Forward {
    fn new(
        base: &str,
        sandbox_id: &str,
        port: u16,
        token: Option<&str>,
        authority: String,
    ) -> Result<Self> {
        let mut routing = HeaderMap::new();
        routing.insert("x-agentenv-sandbox-id", sandbox_id.parse()?);
        routing.insert("x-agentenv-target-port", port.to_string().parse()?);
        if let Some(token) = token {
            let mut value = HeaderValue::from_str(token)?;
            value.set_sensitive(true);
            routing.insert("e2b-traffic-access-token", value);
        }
        let mut builder = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(Duration::from_secs(10));
        if crate::grpc::bypass_proxy_for_base_url(base) {
            builder = builder.no_proxy();
        }
        Ok(Self {
            http: builder.build()?,
            upstream: format!("{}/proxy", base.trim_end_matches('/')),
            authority,
            routing,
            credentials: None,
        })
    }

    fn accepts(&self, headers: &HeaderMap) -> bool {
        // Restrict this authenticated forward to its local origin, including
        // WebSocket requests. A remote page must not drive the user's desktop.
        headers.get(header::HOST).and_then(|v| v.to_str().ok()) == Some(self.authority.as_str())
            && headers.get(header::ORIGIN).is_none_or(|origin| {
                origin.to_str().ok() == Some(format!("http://{}", self.authority).as_str())
            })
            && headers
                .get("sec-fetch-site")
                .is_none_or(|site| matches!(site.to_str(), Ok("same-origin" | "none")))
    }
}

async fn proxy(State(forward): State<Arc<Forward>>, request: Request) -> Response {
    if !forward.accepts(request.headers()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    match relay(&forward, request).await {
        Ok(response) => response,
        Err(error) => {
            eprintln!("Desktop forward: {error:#}");
            (StatusCode::BAD_GATEWAY, "Sandbox desktop is unavailable").into_response()
        }
    }
}

async fn relay(forward: &Forward, mut request: Request) -> Result<Response> {
    let websocket = request
        .headers()
        .get(header::UPGRADE)
        .is_some_and(|v| v.as_bytes().eq_ignore_ascii_case(b"websocket"));
    let upgrade = websocket.then(|| hyper::upgrade::on(&mut request));
    let path = request.uri().path_and_query().map_or("/", |p| p.as_str());
    // `/proxy` is the root route; the server's wildcard needs a nonempty suffix.
    let path = if request.uri().path() == "/" {
        path.trim_start_matches('/')
    } else {
        path
    };
    let url = format!("{}{path}", forward.upstream);
    let (parts, body) = request.into_parts();
    let mut headers = parts.headers;
    strip_hop_headers(&mut headers, websocket);
    // The local Origin has been checked. The data plane rewrites Host, so
    // forward the WebSocket as a non-browser client rather than a false origin.
    if websocket {
        headers.remove(header::ORIGIN);
    }
    // The browser cannot change the sandbox, port, or credentials of a forward.
    for name in [
        "x-api-key",
        "x-access-token",
        "x-agentenv-sandbox-id",
        "e2b-sandbox-id",
        "x-agentenv-target-port",
        "e2b-sandbox-port",
        "e2b-traffic-access-token",
    ] {
        headers.remove(name);
    }
    headers.extend(forward.routing.clone());
    if forward.credentials.is_some() {
        headers.remove(header::AUTHORIZATION);
    }
    let mut upstream = forward
        .http
        .request(parts.method, url)
        .headers(headers)
        .body(reqwest::Body::wrap_stream(body.into_data_stream()));
    if let Some(credentials) = &forward.credentials {
        upstream = upstream.basic_auth(&credentials.username, Some(&credentials.password));
    }
    let upstream = upstream.send().await?;
    let status = upstream.status();
    if forward.credentials.is_some() && status == StatusCode::UNAUTHORIZED {
        // Do not turn a stale/misconfigured deskd credential into a browser
        // password prompt. The user reconnects after fixing the guest service.
        bail!("deskd rejected its saved credentials; restart deskd and reconnect");
    }
    let mut headers = upstream.headers().clone();
    strip_hop_headers(
        &mut headers,
        websocket && status == StatusCode::SWITCHING_PROTOCOLS,
    );
    let body = if let Some(upgrade) = upgrade.filter(|_| status == StatusCode::SWITCHING_PROTOCOLS)
    {
        let mut backend = upstream.upgrade().await?;
        tokio::spawn(async move {
            if let Ok(frontend) = upgrade.await {
                let _ =
                    tokio::io::copy_bidirectional(&mut TokioIo::new(frontend), &mut backend).await;
            }
        });
        Body::empty()
    } else {
        Body::from_stream(upstream.bytes_stream())
    };
    let mut response = Response::new(body);
    *response.status_mut() = status;
    *response.headers_mut() = headers;
    Ok(response)
}

fn strip_hop_headers(headers: &mut HeaderMap, websocket: bool) {
    let connection = headers
        .get(header::CONNECTION)
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_owned();
    for name in connection.split(',').map(str::trim) {
        if !name.is_empty() && !(websocket && name.eq_ignore_ascii_case("upgrade")) {
            headers.remove(name);
        }
    }
    for name in [
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
    ] {
        headers.remove(name);
    }
    if !websocket {
        headers.remove(header::CONNECTION);
        headers.remove(header::UPGRADE);
    } else {
        headers.insert(header::CONNECTION, HeaderValue::from_static("upgrade"));
    }
}

fn open_browser(url: &str) {
    #[cfg(target_os = "macos")]
    let mut command = std::process::Command::new("open");
    #[cfg(target_os = "windows")]
    let mut command = {
        let mut command = std::process::Command::new("cmd");
        command.args(["/C", "start", ""]);
        command
    };
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    let mut command = std::process::Command::new("xdg-open");
    if let Err(error) = command.arg(url).spawn() {
        eprintln!("Could not open the browser ({error}); open the printed URL manually.");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use clap::Parser;
    use futures::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    fn connection_json() -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "version": 1, "port": 6900,
            "authentication": {"scheme": "basic", "username": "ubuntu", "password": "desktop-secret"}
        })).unwrap()
    }

    fn desktop_credentials() -> DesktopCredentials {
        DesktopConnection::parse(&connection_json())
            .unwrap()
            .authentication
    }

    #[test]
    fn validates_connection_contract_without_exposing_secrets() {
        let valid: serde_json::Value = serde_json::from_slice(&connection_json()).unwrap();
        for (field, value) in [
            ("version", serde_json::json!(2)),
            ("port", serde_json::json!(0)),
            (
                "authentication",
                serde_json::json!({"scheme":"unsupported", "username":"ubuntu", "password":"desktop-secret"}),
            ),
            (
                "authentication",
                serde_json::json!({"scheme":"basic", "username":"ubuntu:invalid", "password":"desktop-secret"}),
            ),
            (
                "authentication",
                serde_json::json!({"scheme":"basic", "username":"ubuntu", "password":""}),
            ),
            (
                "authentication",
                serde_json::json!({"scheme":"basic", "username":"ubuntu", "password":{"desktop-secret":true}}),
            ),
        ] {
            let mut input = valid.clone();
            input[field] = value;
            let error = DesktopConnection::parse(&serde_json::to_vec(&input).unwrap())
                .err()
                .expect("invalid connection descriptor");
            assert!(!format!("{error:#}").contains("desktop-secret"));
        }
        let mut alternate_port = valid;
        alternate_port["port"] = serde_json::json!(7900);
        assert_eq!(
            DesktopConnection::parse(&serde_json::to_vec(&alternate_port).unwrap())
                .unwrap()
                .port,
            7900
        );
    }

    async fn process_server(
        output: Vec<u8>,
        exit_code: Option<i32>,
    ) -> (Transport, tokio::task::JoinHandle<()>) {
        use prost::Message as _;
        let router = Router::new().fallback(move |request: Request| {
            let output = output.clone();
            async move {
                assert_eq!(request.uri(), "/process.Process/Start");
                assert_eq!(request.headers()["x-agentenv-sandbox-id"], "sandbox");
                assert_eq!(request.headers()["x-agentenv-target-port"], "49983");
                assert_eq!(request.headers()["x-access-token"], "envd-token");
                assert!(!request.headers().contains_key("x-api-key"));
                let request = to_bytes(request.into_body(), 4096).await.unwrap();
                let start = envd::process::StartRequest::decode(&request[5..]).unwrap();
                let process = start.process.unwrap();
                assert_eq!(process.cmd, "/bin/sh");
                assert_eq!(process.args, ["-c", "if [ -x /agentenv/deskd ]; then exec /agentenv/deskd connect-info; else exec /usr/bin/deskd connect-info; fi"]);
                assert!(start.pty.is_none());
                assert_eq!(start.stdin, Some(false));
                let mut events = vec![process_event::Event::Data(process_event::DataEvent {
                    output: Some(process_event::data_event::Output::Stderr(
                        b"sensitive diagnostic must not reach terminal".to_vec(),
                    )),
                })];
                for part in output.chunks(17) {
                    events.push(process_event::Event::Data(process_event::DataEvent {
                        output: Some(process_event::data_event::Output::Stdout(part.to_vec())),
                    }));
                }
                if let Some(code) = exit_code {
                    events.push(process_event::Event::End(process_event::EndEvent {
                        exit_code: code,
                        exited: true,
                        status: String::new(),
                        error: Some("sensitive error".to_string()),
                    }));
                }
                let mut body = Vec::new();
                for event in events {
                    let payload = StartResponse {
                        event: Some(envd::process::ProcessEvent { event: Some(event) }),
                    }
                    .encode_to_vec();
                    body.push(0);
                    body.extend_from_slice(&(payload.len() as u32).to_be_bytes());
                    body.extend_from_slice(&payload);
                }
                ([(header::CONTENT_TYPE, "application/connect+proto")], body)
            }
        });
        let (address, task) = start(router).await;
        (
            Transport::new(&format!("http://{address}"), "sandbox", Some("envd-token")).unwrap(),
            task,
        )
    }

    #[tokio::test]
    async fn gets_connection_info_through_existing_authenticated_process_api() {
        let (transport, task) = process_server(connection_json(), Some(0)).await;
        let info = DesktopConnection::load(&transport).await.unwrap();
        assert_eq!(info.port, 6900);
        assert_eq!(info.authentication.username, "ubuntu");
        assert_eq!(info.authentication.password, "desktop-secret");
        task.abort();
    }

    #[tokio::test]
    async fn refuses_failed_incomplete_and_oversized_process_output() {
        for (output, exit_code) in [
            (connection_json(), Some(1)),
            (connection_json(), None),
            (vec![b'x'; 16 * 1024 + 1], Some(0)),
        ] {
            let (transport, task) = process_server(output, exit_code).await;
            let error = DesktopConnection::load(&transport)
                .await
                .err()
                .expect("connection must fail");
            assert!(!format!("{error:#}").contains("desktop-secret"));
            assert!(!format!("{error:#}").contains("sensitive"));
            task.abort();
        }
    }

    #[test]
    fn gui_is_opt_in_and_cn_stays_a_shell_alias() {
        assert!(crate::Cli::try_parse_from(["aenv", "cn", "sandbox"]).is_ok());
        assert!(crate::Cli::try_parse_from(["aenv", "connect", "sandbox", "--gui"]).is_ok());
        assert!(crate::Cli::try_parse_from([
            "aenv",
            "connect",
            "sandbox",
            "--gui-port",
            "0",
            "--gui"
        ])
        .is_err());
        assert!(crate::Cli::try_parse_from(["aenv", "connect", "sandbox", "--no-open"]).is_err());
    }

    async fn start(router: Router) -> (String, tokio::task::JoinHandle<()>) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let address = listener.local_addr().unwrap().to_string();
        let task = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        (address, task)
    }

    async fn forward_to(
        base: &str,
        credentials: Option<DesktopCredentials>,
    ) -> (String, tokio::task::JoinHandle<()>) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let authority = listener.local_addr().unwrap().to_string();
        let mut forward = Forward::new(
            base,
            "sandbox",
            6900,
            Some("private-traffic-token"),
            authority.clone(),
        )
        .unwrap();
        forward.credentials = credentials;
        let router = Router::new().fallback(proxy).with_state(Arc::new(forward));
        let task = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        (format!("http://{authority}"), task)
    }

    #[tokio::test]
    async fn streams_files_preserves_application_auth_and_rejects_other_origins() {
        let router = Router::new().fallback(|request: Request| async move {
            assert_eq!(request.uri().to_string(), "/proxy/api/upload?name=a%20b");
            assert_eq!(request.headers()["x-agentenv-sandbox-id"], "sandbox");
            assert_eq!(request.headers()["x-agentenv-target-port"], "6900");
            assert_eq!(
                request.headers()["e2b-traffic-access-token"],
                "private-traffic-token"
            );
            assert_eq!(
                request.headers()[header::AUTHORIZATION],
                "Basic app-credential"
            );
            assert!(!request.headers().contains_key("x-api-key"));
            let data = to_bytes(request.into_body(), 2 * 1024 * 1024)
                .await
                .unwrap();
            ([(header::CONTENT_TYPE, "application/octet-stream")], data)
        });
        let (upstream, upstream_task) = start(router).await;
        let (url, task) = forward_to(&format!("http://{upstream}"), None).await;
        let http = reqwest::Client::new();
        for (name, value) in [
            ("origin", "https://foreign.invalid"),
            ("host", "foreign.invalid"),
            ("sec-fetch-site", "cross-site"),
        ] {
            let response = http.get(&url).header(name, value).send().await.unwrap();
            assert_eq!(response.status(), StatusCode::FORBIDDEN);
        }
        let payload = vec![42u8; 1024 * 1024];
        let response = http
            .post(format!("{url}/api/upload?name=a%20b"))
            .header("x-agentenv-sandbox-id", "other-sandbox")
            .header("x-agentenv-target-port", "22")
            .header("e2b-traffic-access-token", "untrusted-token")
            .header("x-api-key", "must-not-leave-client")
            .header(header::AUTHORIZATION, "Basic app-credential")
            .body(payload.clone())
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.bytes().await.unwrap().as_ref(), payload);
        task.abort();
        upstream_task.abort();
    }

    #[tokio::test]
    async fn authenticates_http_without_browser_credentials_and_overrides_stale_login() {
        let router = Router::new().fallback(|request: Request| async move {
            assert_eq!(request.uri(), "/proxy");
            assert_eq!(
                request.headers()[header::AUTHORIZATION],
                "Basic dWJ1bnR1OmRlc2t0b3Atc2VjcmV0"
            );
            "desktop ready"
        });
        let (upstream, upstream_task) = start(router).await;
        let (url, task) =
            forward_to(&format!("http://{upstream}"), Some(desktop_credentials())).await;
        let http = reqwest::Client::new();
        for request in [
            http.get(&url),
            http.get(&url)
                .header(header::AUTHORIZATION, "Basic stale-browser-login"),
        ] {
            let response = request.send().await.unwrap();
            assert_eq!(response.status(), StatusCode::OK);
            assert!(!response.headers().contains_key(header::WWW_AUTHENTICATE));
            assert!(!response.headers().contains_key(header::AUTHORIZATION));
            assert_eq!(response.text().await.unwrap(), "desktop ready");
        }
        task.abort();
        upstream_task.abort();
    }

    #[tokio::test]
    async fn rejected_saved_credentials_never_trigger_a_browser_login_prompt() {
        let router = Router::new().fallback(|| async {
            (
                StatusCode::UNAUTHORIZED,
                [(header::WWW_AUTHENTICATE, "Basic realm=desktop")],
            )
        });
        let (upstream, upstream_task) = start(router).await;
        let (url, task) =
            forward_to(&format!("http://{upstream}"), Some(desktop_credentials())).await;
        let response = reqwest::get(url).await.unwrap();
        assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
        assert!(!response.headers().contains_key(header::WWW_AUTHENTICATE));
        assert_eq!(
            response.text().await.unwrap(),
            "Sandbox desktop is unavailable"
        );
        task.abort();
        upstream_task.abort();
    }

    #[tokio::test]
    async fn websocket_upgrade_relays_binary_frames_and_close() {
        let router = Router::new().fallback(|mut request: Request| async move {
            assert_eq!(request.uri(), "/proxy/websocket");
            assert_eq!(
                request.headers()[header::AUTHORIZATION],
                "Basic dWJ1bnR1OmRlc2t0b3Atc2VjcmV0"
            );
            assert_eq!(
                request.headers()["e2b-traffic-access-token"],
                "private-traffic-token"
            );
            let key = request.headers()["sec-websocket-key"].as_bytes();
            let accept = tokio_tungstenite::tungstenite::handshake::derive_accept_key(key);
            let upgrade = hyper::upgrade::on(&mut request);
            tokio::spawn(async move {
                let socket = TokioIo::new(upgrade.await.unwrap());
                let mut ws = tokio_tungstenite::WebSocketStream::from_raw_socket(
                    socket,
                    tokio_tungstenite::tungstenite::protocol::Role::Server,
                    None,
                )
                .await;
                while let Some(Ok(message)) = ws.next().await {
                    if message.is_close() {
                        let _ = ws.close(None).await;
                        break;
                    }
                    ws.send(message).await.unwrap();
                }
            });
            Response::builder()
                .status(StatusCode::SWITCHING_PROTOCOLS)
                .header(header::CONNECTION, "Upgrade")
                .header(header::UPGRADE, "websocket")
                .header("sec-websocket-accept", accept)
                .body(Body::empty())
                .unwrap()
        });
        let (upstream, upstream_task) = start(router).await;
        let (url, task) =
            forward_to(&format!("http://{upstream}"), Some(desktop_credentials())).await;
        let (mut ws, _) = connect_async(format!("{}/websocket", url.replacen("http", "ws", 1)))
            .await
            .unwrap();
        let payload = Message::Binary(vec![7; 256 * 1024].into());
        ws.send(payload.clone()).await.unwrap();
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(5), ws.next())
                .await
                .unwrap()
                .unwrap()
                .unwrap(),
            payload
        );
        ws.close(None).await.unwrap();
        task.abort();
        upstream_task.abort();
    }

    #[tokio::test]
    async fn redirects_are_returned_without_following_to_other_hosts() {
        let router = Router::new().fallback(|request: Request| async move {
            assert_eq!(request.uri(), "/proxy");
            (
                StatusCode::FOUND,
                [(header::LOCATION, "https://external.invalid/login")],
            )
        });
        let (upstream, upstream_task) = start(router).await;
        let (url, task) =
            forward_to(&format!("http://{upstream}"), Some(desktop_credentials())).await;
        let http = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap();
        let response = http.get(url).send().await.unwrap();
        assert_eq!(response.status(), StatusCode::FOUND);
        assert_eq!(
            response.headers()[header::LOCATION],
            "https://external.invalid/login"
        );
        task.abort();
        upstream_task.abort();
    }
}
