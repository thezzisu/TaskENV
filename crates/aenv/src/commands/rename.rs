use crate::client::Client;
use anyhow::Result;
use clap::Args as ClapArgs;

#[derive(ClapArgs)]
pub struct Args {
    /// Sandbox ID or current name
    #[arg(add = crate::commands::completion::add_active_sandbox_candidates())]
    sandbox: String,
    /// New unique sandbox name
    name: String,
}

pub fn run(args: Args) -> Result<()> {
    let client = Client::from_env()?;
    let sandbox_id = client.resolve_sandbox_id(&args.sandbox)?;
    client.rename_sandbox(&sandbox_id, &args.name)?;
    println!("Renamed {sandbox_id} to {}", args.name);
    Ok(())
}
