# Habitat Demo
New to Habitat?  Check out the docs and tutorials [here](http://habitat.sh).

## Purpose
This is a simple Rust webapp, but we're going to deploy it in a multi-tiered environment to explore Habitat.

## Prereqs
If you want to muck with the application code itself, you'll need a recent version of Rust (I'm using 1.11.0-nightly).  We'll be deploying the app with Docker, so you'll need Docker installed.  You'll need docker-compose, which is included with the Docker Toolbox.  Finally, you'll need a Habitat binary.  Grab one from [here](https://www.habitat.sh/docs/get-habitat/), extract it, and drop the `hab` binary in your path.  

Habitat currently does not support Windows, so you will need an OS X or Linux machine if you want to run any `hab` commands.  The final deployment is fully based on Docker containers, so you can follow along and deploy the final product in Docker on a Windows machine.

## The App
The application itself is a super simple Rust web app.  It takes a parameter of `/<name>` and outputs the number of times it has seen that name, as well as identifying which node is responding.  

```
$ curl http://192.168.99.101:8080/nolan
Hello nolan!  I have seen you 1 times!<br><br>You are accessing node 1.

$ curl http://192.168.99.101:8080/nolan
Hello nolan!  I have seen you 2 times!<br><br>You are accessing node 1.
```

The application uses Redis to store the counter and node information, so if you stop and restart the cluster, you'll see these numbers reset.

We store our configuration in `config/config.toml`:

```[app]
port = "8080"  # The port our webapp will listen on
greeting = "Hello" # The text we will use to greet the user
redis_host = "localhost" # Redis host to use
redis_port = "6379" # Redis port
```

The actual application code lives in `src/main.rs`.  It uses the [Nickel framework](http://nickel.rs) take requests and update Redis and get the new count of how many times we've seen a certain name.

## The Plan
![ATeam](https://estherspetition.files.wordpress.com/2015/04/whenaplancomestogether.jpg)

So we have an awesome app that's sure to be the talk of the internet, now what?  Let's build a Habitat package!