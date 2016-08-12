#[macro_use]
extern crate nickel;
extern crate toml;
extern crate redis;

use nickel::Nickel;
use std::fs::File;
use std::io::prelude::*;
use std::path::Path;
use redis::Commands;

fn main() {
    let config_path = Path::new("config/config.toml");

    let mut config_file = File::open(&config_path).unwrap();

    let mut config_string = String::new();
    config_file.read_to_string(&mut config_string).unwrap();

    let config: toml::Value = config_string.parse().unwrap();
    let port = config.lookup("app.port").unwrap();
    let greeting = config.lookup("app.greeting").unwrap().clone();
    let redis_host = config.lookup("app.redis_host").unwrap().clone();
    let redis_port = config.lookup("app.redis_port").unwrap().clone();

    let mut server = Nickel::new();

    let node = increment_count(redis_host.as_str().unwrap().to_string(),
                               redis_port.as_str().unwrap().to_string(),
                               "node".to_string())
        .unwrap()
        .to_string();

    server.utilize(router! {
        get "/:name" => |req, _res| {
            let name = req.param("name").unwrap().to_string();
            let count = increment_count(redis_host.as_str().unwrap().to_string(), redis_port.as_str().unwrap().to_string(), name.clone());
            format!("{} {}!  I have seen you {} times!", greeting.as_str().unwrap().to_string(), name, count.unwrap().to_string())
        }
    });

    let server_string = format!("0.0.0.0:{}", port.as_str().unwrap()).to_string();
    server.listen(&*server_string);
}

fn increment_count(host: String, port: String, name: String) -> redis::RedisResult<isize> {
    let conn_string = format!("redis://{}:{}/", host, port);
    let client = try!(redis::Client::open(&*conn_string));
    let conn = try!(client.get_connection());

    conn.incr(name, 1)
}
