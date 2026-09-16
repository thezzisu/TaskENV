//! Presentation only. Keep the upstream CLI and compatibility state unchanged.
fn taskenv() -> bool {
    std::env::args_os().next().is_some_and(|path| {
        std::path::Path::new(&path)
            .file_stem()
            .is_some_and(|name| name == "taskenv")
    })
}

pub fn name() -> &'static str {
    if taskenv() {
        "taskenv"
    } else {
        "aenv"
    }
}

pub fn about() -> &'static str {
    if taskenv() {
        "TaskENV — everyday task sandboxes"
    } else {
        "AENV CLI"
    }
}

pub fn version() -> &'static str {
    if taskenv() {
        include_str!("VERSION").trim()
    } else {
        env!("CARGO_PKG_VERSION")
    }
}
