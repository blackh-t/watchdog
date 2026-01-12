use actix_web::{App, HttpServer, middleware::Logger};
use env_logger::Env;
use log::{error, warn};
use std::env;
mod handler;
mod routes;

use crate::routes::webhook_routes;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(Env::default().default_filter_or("info")); // Activate logger.

    // PORT is defined in webapp service.
    let port: u16 = match env::var("TS_PORT") {
        Ok(val) => val.parse().expect("TypeError: Port is not U16"),
        Err(e) => {
            error!("Failed to fetch env 'TS_PORT' from API Gateway service: {e}");
            warn!("Use default port 3000");
            3000
        }
    };

    let local_ip = "127.0.0.1";
    let n_cpu = num_cpus::get();
    let n_queue = n_cpu as u32 * 2;

    // Initial HTTP workers to handle inncomming TCP connections.
    HttpServer::new(|| {
        App::new()
            .wrap(Logger::new("%a\t | %s\t | %Dms\t | %r\t"))
            .configure(webhook_routes)
    })
    .workers(n_cpu)
    .backlog(n_queue)
    .bind((local_ip, port))?
    .run()
    .await
}
