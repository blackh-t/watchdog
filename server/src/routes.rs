use crate::handler::git_pull_service::*;
use actix_web::{
    HttpResponse,
    web::{self, head, post, scope},
};

/// Executes git pull service on newly git commit.
pub fn webhook_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        scope("/webhook")
            .route("", post().to(git_pull))
            .route("", head().to(HttpResponse::MethodNotAllowed)),
    );
}
