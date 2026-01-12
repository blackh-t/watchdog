use actix_web::{HttpRequest, HttpResponse, Responder};
use hex;
use hmac::{Hmac, Mac};
use log::{error, warn};
use sha2::Sha256;
use std::{env, process::Command};

/// This function is used to run a script to pull the lastest commmit,
/// then move and run "run_on_pull.sh".
pub async fn git_pull(req: HttpRequest, body: String) -> impl Responder {
    // Get Signature.
    let sign = req
        .headers()
        .get("X-Hub-Signature-256")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    // Verify signature.
    let secret = env::var("SECRET_TOKEN").unwrap_or("".to_string());
    if sign != generate_sign(&secret, body.as_ref()) {
        error!("Invalid signature");
        return HttpResponse::Unauthorized().body("Invalid Signature");
    }

    // Run the script.
    warn!("Webhook authorized, running git pull service... .. .");
    let git_pull_script = env::var("SCRIPT_PATH").unwrap();
    Command::new(git_pull_script)
        .status()
        .expect("[ Invalid ] -- PATH");

    HttpResponse::Ok().body("Webhook received")
}

fn generate_sign(secret: &str, payload: &[u8]) -> String {
    type HmacSha256 = Hmac<Sha256>;

    // Signature = secret + payload.
    let mut hmac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
    hmac.update(payload);

    // Return expected sign in hex.
    let res = hmac.finalize().into_bytes();
    format!("sha256={}", hex::encode(res))
}

// Tests
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_sign() {
        let secret = "It's a Secret to Everybody";
        let payload = "Hello, World!".as_bytes();

        let signature = generate_sign(secret, payload);
        let expected = "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17";

        assert_eq!(signature, expected);
    }
}
