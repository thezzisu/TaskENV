use crate::client::Client;
use anyhow::Result;
use clap::Args as ClapArgs;

#[derive(ClapArgs)]
pub struct Args {
    #[arg(add = crate::commands::completion::add_active_sandbox_candidates())]
    sandbox_id: String,
}

pub fn run(args: Args) -> Result<()> {
    let client = Client::from_env()?;
    let sandbox_id = client.resolve_sandbox_id(&args.sandbox_id)?;
    client.delete_sandbox(&sandbox_id)?;
    println!("Deleted sandbox {}", args.sandbox_id);
    Ok(())
}
