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

Our plan is located in the `habitat` directory.  

```
tree habitat
habitat
├── config
│   └── config.toml
├── default.toml
├── hooks
│   ├── init
│   └── run
└── plan.sh
```

Check out the plan syntax docs [here](https://www.habitat.sh/docs/reference/plan-syntax/). Let's checkout the files in our plan.  

#### plan.sh
This is the main file of a plan.  It contains metadata about the package we will be building, as well as a few [callbacks](https://www.habitat.sh/docs/reference/plan-syntax/#callbacks) that we'll use to customize how our application gets unpacked and built.

metadata:

```
pkg_origin=nsdavidson   
pkg_name=rust-hello-world
pkg_version=0.1.0
pkg_maintainer="Nolan Davidson <ndavidson@chef.io>"
pkg_license=()
```
source information:

```
pkg_source=things
pkg_shasum=stuff
```
If we were pulling our source code from an external source (such as GitHub releases), we would define that URL and the expected shasum here.  We have populated that with dummy values here because we are building code from this repo.

dependency information:

```
pkg_deps=(core/coreutils core/gcc-libs core/glibc)
pkg_build_deps=(core/openssl core/rust core/cacerts core/gcc core/gcc-libs core/glibc)
```
Here we define two sets of dependencies.  The build dependencies are the packages required execute the build of our package.  The other set contains the run time dependencies.  The packages in these lists refer to Habitat packages.  

runtime information:

```
pkg_expose=(8080)
```
The `pkg_expose` value will be used later when we build a Docker image for our application.  

Callbacks:

```
do_download() {
  return 0
}

do_unpack() {
  cp -a ../ ${HAB_CACHE_SRC_PATH}
}

do_verify() {
  return 0
}
do_build() {
  env SSL_CERT_FILE=$(pkg_path_for cacerts)/ssl/cert.pem cargo build --release
}

do_install() {
  cp ../target/release/rust-hello-world ${pkg_prefix}
}
```
Here we can override the default Habitat build behavior.  You can see in the `do_build()` function that we are using `cargo` to build our Rust application.

#### default.toml
We looked at the configuration file for our application earlier, but this was a hard coded version.  We will be using Habitat's configuration functionality to render our config file when we deploy.  This file holds our default values that Habitat will use when creating our configuration.  We'll look at that file next.

#### config/config.toml
```
[app]
port = "{{cfg.port}}"
greeting = "{{cfg.greeting}}"

{{~#if bind.has_redis}}
{{~#each bind.redis.members}}
redis_host = "{{ip}}"
redis_port = "{{port}}"
{{~/each}}
{{~else}}
redis_host = "{{cfg.redis_host}}"
redis_port = "{{cfg.redis_port}}"
{{~/if}}
```
Here is where we template our configuration file out.  These templates are rendered using [Handlebars](http://handlebarsjs.com/).  The values prefixed with `cfg` are user-tunable values.  These will be populated by the values in the `default.toml` file we looked at earlier unless overriden elsewhere.  We will look at ways to set and update these values later.

The other interesting part of this file is the use of a [binding](https://www.habitat.sh/docs/run-packages-binding/).  Bindings allow us to expose other [service groups](https://www.habitat.sh/docs/run-packages-service-groups/) to our service group.  We will see how to set these bindings later, but for now let's follow through this block assuming a binding to a `redis` service group has been created when we launch our app.

```
{{~#if bind.has_redis}}  				# Checks to see if a redis binding exists 
{{~#each bind.redis.members}}			# If it does, loop through each member of the group
redis_host = "{{ip}}"					# Render out config lines setting the host and port
redis_port = "{{port}}"					# for each member
{{~/each}}						
{{~else}}									# If no binding exists, use the configuration values
redis_host = "{{cfg.redis_host}}"
redis_port = "{{cfg.redis_port}}"
{{~/if}}
```

This is a little bit of a hack, because our app only supports one Redis host.  We could just pull the values from the first member of the group, but we're only going to launch one Redis host so the loop is ok for now.

We can see that if the Redis binding exists, then we will dynamically pull these values from the current members of the service group.  If it's not, then we fall back to our configuration values.  This logic could also be reversed, if we prefer to have our configuration settings take precendence over the service group binding.

#### hooks
[Hooks](https://www.habitat.sh/docs/reference/plan-syntax/#hooks) provide the ability to write custom code to handle certain lifecycle events.  We have defined two hooks, `init` and `run`.  The `init` hook runs when a Habitat topology starts, and the `run` hook runs when your application is starting up.  

###### init
```
#!/bin/sh
cp {{pkg.path}}/rust-hello-world {{pkg.svc_path}}
```
This hook simply copies our executable from the package path to the svc_path, which is where Habitat will actually run our application from.

##### run
```
#!/bin/sh
killall rust-hello-world || true
cd {{pkg.svc_path}}
./rust-hello-world
```
This hook is responsible for starting the application.  First we have to kill any existing process, or we'll have bad times restarting the service later.  Then we just change into the service path for the package and execute our application.

## Build it!
Now that we have an application and a plan to build our Habitat package, let's build it!  If you're on a Windows machine, you can jump straight to the deploy section.  

The first step is to enter a Habitat [studio](https://www.habitat.sh/docs/concepts-studio/).  A studio is a minminal environment for building Habitat packages.

*NOTE*: Make sure to enter the studio from the root of the `rust-hello-world` project.

```
$ hab studio -k nsdavidson enter
```

The `-k` argument imports the origin keys for the specified origin, so this should be whatever origin you want to publish to.  If you want to follow along and do the build yourself, you should create an origin keypair for your origin using `hab origin key generate your_origin_name`.  Update the `plan.sh` file with your origin, and use that as the `-k` argument in the studio command above.

Once you've successfully entered the studio, you should see a prompt something like this:

```
[1][default:/src:0]#
```

Once you're in the studio environment, we can build our Habitat artifact by executing the `build` command.  This command will look for a `habitat` directroy in the current directory, and we have one of those!
 
```
[default:/src:0]# build
```

If you watch the terminal, you'll see the studio pull in all the packages we declared as build dependencies in our `plan.sh` file, as well as any transitive dependencies.  These depedencies will pull by default from the public Depot, which is a repository for Habitat packages.  Then you'll see the actual `cargo` build happen.  Once the Rust application has built successfully, you will see the Habitat artifact get created in the form of a `.hart` file.  This hart file is a signed tarball of your application.  At the end of a successful build, you'll see something like this at the bottom of the output:

```
rust-hello-world: I love it when a plan.sh comes together.
rust-hello-world:
rust-hello-world: Build time: 4m2s
```

So at this point we've created a Habitat package.  We could upload it to the public Depot, or run it using the Habitat supervisor (packages can only run on Linux systems currently).  In this case, we want to use Docker to deploy to our app locally.  We could create a Dockerfile that installs Habitat and runs our package, but we don't have to.  Habitat comes with an export command that can do that for us!  Currently Habitat can export to Docker, ACI, and Mesos formats.  Let's export a Docker image.

```
[default:/src:0]# hab pkg export docker nsdavidson/rust-hello-world
```
If you changed the origin name, you will need to replace `nsdavidson` with your origin name in the export command.

Let's exit the studio, back into our original shell and see if we have our Docker image.

```
[5][default:/src:0]# exit
logout
$ docker images
REPOSITORY                                  TAG                    IMAGE ID            
nsdavidson/rust-hello-world                 0.1.0-20160617152923   b519b618d2a1
nsdavidson/rust-hello-world                 latest                 b519b618d2a1
...
```
There's our Docker image, which is configured to run our rust-hello-world packge using the Habitat supervisor.  If you want to share your image, you can push it up to the Docker Hub or another Docker repo, but for now lets continue working locally.

#### Run it!
Let's try running our new image.

```
$ docker run -it -p 8080:8080 nsdavidson/rust-hello-world
hab-sup(MN): Starting nsdavidson/rust-hello-world
hab-sup(GS): Supervisor 172.17.0.2: f913ed7b-b23f-4cd1-8a0f-022345a7cac2
hab-sup(GS): Census rust-hello-world.default: efa0530b-76c4-4867-9b75-f44963483af5
hab-sup(GS): Starting inbound gossip listener
hab-sup(GS): Starting outbound gossip distributor
hab-sup(GS): Starting gossip failure detector
hab-sup(CN): Starting census health adjuster
hab-sup(SC): Updated config.toml
hab-sup(TP): Restarting because the service config was updated via the census
rust-hello-world(SV): Starting
hab-sup(SV): rust-hello-world - process 58 died with exit code 101
hab-sup(SV): rust-hello-world - Service exited
rust-hello-world(SV): Starting
hab-sup(SV): rust-hello-world - process 62 died with exit code 101
hab-sup(SV): rust-hello-world - Service exited
rust-hello-world(SV): Starting
hab-sup(SV): rust-hello-world - process 66 died with exit code 101
hab-sup(SV): rust-hello-world - Service exited
```
We get off to a good start.  You can see the `hab-sup` process start up, but when it tries to start our application we go into a crash/restart loop.  Remember that our application accesses Redis on startup to find its node number.  We don't have a Redis instance running, so our app is failing to start.  Let's fire up a Redis container.

```
$ docker run -it nsdavidson/redis
hab-sup(MN): Starting core/redis
hab-sup(GS): Supervisor 172.17.0.2: 4de37b5a-08d9-4246-b316-4e783e34370e
hab-sup(GS): Census redis.default: 654e19ae-9d50-463a-acd7-417303382970
hab-sup(GS): Starting inbound gossip listener
hab-sup(GS): Starting outbound gossip distributor
hab-sup(GS): Starting gossip failure detector
hab-sup(CN): Starting census health adjuster
hab-sup(SC): Updated redis.config
hab-sup(TP): Restarting because the service config was updated via the census
redis(SV): Starting
redis(O):                 _._
redis(O):            _.-``__ ''-._
redis(O):       _.-``    `.  `_.  ''-._           Redis 3.0.7 (00000000/0) 64 bit
redis(O):   .-`` .-```.  ```\/    _.,_ ''-._
redis(O):  (    '      ,       .-`  | `,    )     Running in standalone mode
redis(O):  |`-._`-...-` __...-.``-._|'` _.-'|     Port: 6379
redis(O):  |    `-._   `._    /     _.-'    |     PID: 88
redis(O):   `-._    `-._  `-./  _.-'    _.-'
redis(O):  |`-._`-._    `-.__.-'    _.-'_.-'|
redis(O):  |    `-._`-._        _.-'_.-'    |           http://redis.io
redis(O):   `-._    `-._`-.__.-'_.-'    _.-'
redis(O):  |`-._`-._    `-.__.-'    _.-'_.-'|
redis(O):  |    `-._`-._        _.-'_.-'    |
redis(O):   `-._    `-._`-.__.-'_.-'    _.-'
redis(O):       `-._    `-.__.-'    _.-'
redis(O):           `-._        _.-'
redis(O):               `-.__.-'
redis(O):
redis(O): 88:M 17 Jun 16:42:09.528 # WARNING: The TCP backlog setting of 511 cannot be enforced because /proc/sys/net/core/somaxconn is set to the lower value of 128.
redis(O): 88:M 17 Jun 16:42:09.528 # Server started, Redis version 3.0.7
redis(O): 88:M 17 Jun 16:42:09.528 # WARNING overcommit_memory is set to 0! Background save may fail under low memory condition. To fix this issue add 'vm.overcommit_memory = 1' to /etc/sysctl.conf and then reboot or run the command 'sysctl vm.overcommit_memory=1' for this to take effect.
redis(O): 88:M 17 Jun 16:42:09.528 # WARNING you have Transparent Huge Pages (THP) support enabled in your kernel. This will create latency and memory usage issues with Redis. To fix this issue run the command 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' as root, and add it to your /etc/rc.local in order to retain the setting after a reboot. Redis must be restarted after THP is disabled.
redis(O): 88:M 17 Jun 16:42:09.528 * The server is now ready to accept connections on port 6379
```
The `nsdavidson/redis` image simply runs the Redis Habitat package.  We can see the `hab-sup` process start up and successfully launch Redis.  Super...so how can we tell our application how to access it? We could grab the IP of our Redis container and put it in our `default.toml` file.  We could use a Docker link to connect them.  Instead, let's use the binding we talked about earlier when we looked at the config file template.

### Supervisor rings and service groups
The Habitat supervisor can link with other supervisors to form a ring.  The supervisors in a ring maintain a census and share configuration data.  Service groups consist of one or more running instances of an application with a shared configuration and topology.  Every application running under the Habitat supervisor is part of a service group.

Let's look at some of the earliest lines of output from our Redis container starting up:

```
hab-sup(MN): Starting core/redis
hab-sup(GS): Supervisor 172.17.0.2: 4de37b5a-08d9-4246-b316-4e783e34370e
hab-sup(GS): Census redis.default: 654e19ae-9d50-463a-acd7-417303382970
```
We can see that we are starting the `core/redis` package, that our supervisor is at the address 172.17.0.2, and that our service group is named `redis.default`.  A custom service group name can be provided at application start up with the `--group` option.

### Bindings
Now that we see we have a supervisor running and a service group, let's go back to bindings.  Bindings allow us to expose data about other service groups to another service group, and use that data in our configuration.  So we need to start up our application and give it two pieces of information.  The peer supervisor to connect to, and the binding to create.  Make sure the Redis container is still running, and then run this command.  Note that your IP addresses might be different.  Make sure to grab your peer IP from the output above.

```
$ docker run -it -p 8080:8080 nsdavidson/rust-hello-world --bind redis:redis.default --peer 172.17.0.2
```
This starts up the supervisor, tells it to run our rust-hello-world package, tells it to use our supervisor running Redis as a peer (172.17.0.2), and bind the `redis.default` service group to the name `redis`.  Recall this bit from our config template:

```
{{~#if bind.has_redis}}
{{~#each bind.redis.members}}
redis_host = "{{ip}}"
redis_port = "{{port}}"
{{~/each}}
{{~else}}
redis_host = "{{cfg.redis_host}}"
redis_port = "{{cfg.redis_port}}"
{{~/if}}
```
Without declaring the `redis` binding, our application configuration would use the config settings.  In this case we have created the binding, and so the top part of our `if` block will run and pull names and port from the members of the `redis.default` service group.  The binding also gives us the flexibility to have one configuration template that can work for any group of Redis services.  Imagine we had a `redis.dev` and a `redis.prod` service group.  We could set the binding to either and not have to make any changes to our app.

Now our application should start up successfully without output like this:

```
hab-sup(MN): Starting nsdavidson/rust-hello-world
hab-sup(GS): Supervisor 172.17.0.3: 32a18db4-c5d0-414d-bd60-09a68cdba19c
hab-sup(GS): Census rust-hello-world.default: 7093c9e7-4f58-4013-9288-3a59462fc084
hab-sup(GS): Starting inbound gossip listener
hab-sup(GS): Joining gossip peer at 172.17.0.2:9634
hab-sup(GS): Starting outbound gossip distributor
hab-sup(GS): Starting gossip failure detector
hab-sup(CN): Starting census health adjuster
hab-sup(SC): Updated config.toml
hab-sup(TP): Restarting because the service config was updated via the census
rust-hello-world(SV): Starting
rust-hello-world(O): Listening on http://0.0.0.0:8080
rust-hello-world(O): Ctrl-C to shutdown server
```
We can see the supervisor start up, create a new service group for our app, and join it's peer at 172.17.0.2.  Let's test our app make sure it's working.

```
$ curl http://<ip_of_your_docker_host>:8080/me
Hello me!  I have seen you 1 times!<br><br>You are accessing node 1.
$ curl http://<ip_of_your_docker_host>:8080/me
Hello me!  I have seen you 2 times!<br><br>You are accessing node 1.
$ curl http://<ip_of_your_docker_host>:8080/you
Hello you!  I have seen you 1 times!<br><br>You are accessing node 1.
```
Nice!  Our app is running and working as expected.

## Reconfigure it!
So our app is up and running, but I'm starting to feel our greeting is a bit formal.  "Hello <name>!" soounds so impersonal...I think we should change our greeting from "Hello" to "Sup".  How can we change it?  We exposed it as a configuration value, so thankfully we don't have to go back into the application code.  We could change it in our `default.toml` file and build a new package, but ain't nobody got time for that!  Let's update the config on the fly.  Jump back into the studio and let's push out a new config value for `greeting`.

```
$ hab studio -k nsdavidson enter
[default:/src:0]# echo 'greeting = "Sup"' | hab config apply --peer 172.17.0.3 rust-hello-world.default 1
» Applying configuration
↑ Applying configuration for rust-hello-world.default into ring via ["172.17.0.3:9634"]
Joining peer: 172.17.0.3:9634
Configuration applied to: 172.17.0.3:9634
★ Applied configuration.
```
So we just piped in the updated TOML key/value into the `hab config apply` command.  We gave it a peer to send the information to, and what service group it applied for.  The 1 at the end is a version specifier.

Over in the terminal where you have the application container running, you should see the following output:

```
Writing new file from gossip: /hab/svc/rust-hello-world/gossip.toml
hab-sup(SC): Updated config.toml
rust-hello-world(SV): Stopping
hab-sup(SV): rust-hello-world - process 59 died with signal 15
hab-sup(SV): rust-hello-world - Service exited
rust-hello-world(SV): Starting
rust-hello-world(O): Listening on http://0.0.0.0:8080
rust-hello-world(O): Ctrl-C to shutdown server
```
The Habitat supervisor running our application saw the configuration change, applied it, and restarted the app.  Let's test it again:

```
$ curl http://<ip_of_your_docker_host>:8080/me
Sup me!  I have seen you 3 times!<br><br>You are accessing node 2.
```
Much better!  Our app is now speaking the hip lingo, and you can see that it maintained our counter, because the Redis service was unaffected.  Unfortunately that also makes our node count inaccurate, as we still just have the one despite it saying we're on node #2.  Which brings up a good point.  Our app is so killer, it will surely be trending on HN and reddit within minutes of launch, so we might want to think about being able to run multiple instances of our application server in parallel.  Before we tackle that, let's shut down these containers we've manually started and move our environment configuration into Docker Compose.

#### Docker Compose
Docker Compose is a tool that ships as part of the Docker toolbox that lets us define our environment, which is quickly growing to multiple types of nodes.  There's a docker-compose.yml file in the root of this project, but let's just look at the part that's relevant to us a the moment:

```
version: "2"
services:
  app:
    image: nsdavidson/rust-hello-world
    command: --peer redis --bind redis:redis.default
    depends_on:
      - redis
    links:
      - redis
     ports:
     	- "8080:8080"
  redis:
    image: nsdavidson/redis:latest
```
So we define our `app` service and our `redis` services.  The `redis` service is super simple.  Just pull down the Redis container and run it with all defaults.  Our `app` service has a few more options.  We use `depends_on: - redis` to make sure that the Redis container comes up first, since our app needs it to start up properly.  Adding `links: -redis` allows us to access that container by the name `redis`.  By default, the Docker image exported from Habitat will start up the supervisor with our `rust-hello-world` package.  We use the `command:` configuration option to pass in some extra parameters.  We're telling it to start up and use the `redis` supervisor as it's peer (which we can do because we declared the link) and to bind the `redis.default` service group to `redis`.

If you want to verify this works, you can put this in a temporary file and run the following:

```$ docker-compose up -f tempfile```

This will spin up both services and you should be able to hit the application just like we did before, using the IP address of your Docker host.  When you're ready to tear it down, just run:

```$ docker-compose down```

#### Scale it!
Now that we can spin up new application environments quickly and easily, lets circle back to the issue of scaling.  We're not going to worry about Redis right now, lets just focus on being able to run multiple application servers.  Our application persists the count data to Redis, so we can easily run multiple app servers.  But we can't spin up mutliple containers binding to the same port, and even if we deployed across multiple hosts, we would need a way to get traffic hitting one IP/port distributed across all the app servers.  Load balancing to the rescue!

We're going to use a custom version of the HAProxy Habitat package.  There is a PR in for the currently version available as `core/haproxy` to make it match mine, but at the time of this writing it has not been merged.  The only change is making the `haproxy.conf` file look like this:

```
global
    maxconn {{cfg.maxconn}}

defaults
    mode {{cfg.mode}}
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend http-in
    bind {{cfg.bind}}
    default_backend default

backend default
{{#if bind.has_backend }}
{{~#each bind.backend.members}}
    server {{ip}} {{ip}}:{{port}}
{{~/each}}
{{~else}}
{{~#each cfg.server}}
    server {{name}} {{host_or_ip}}:{{port}}
{{~/each}}
{{~/if}}
```
The current version of this package only looks for backend servers defined in the configuration.  The updated package uses the above config to look for a service group binding named `backend` and loop through those to populate the backends for HAProxy.  As we will see, this allows us to add more backend nodes without having to push config changes.

I've published a Docker container that uses this version of the HAProxy package, and that's what we're using in our final docker-compose.yml.  Here's the bit we added to configure the load balancer.

```
lb:
    image: nsdavidson/haproxy
    command: --peer app --bind backend:rust-hello-world.default
    links:
      - app
    environment:
      HAB_HAPROXY: bind="*:8080"
    ports:
      - "8080:8080"
    depends_on:
      - app
```
Most of this is familiar from looking at the configs for the app and Redis services.  We're using the `nsdavidson/haproxy` Docker image, setting up a link to the app service, and depending on the app service to start first.  We're binding our `rust-hello-world.default` service group to the `backend` name we talked about in the HAProxy config.  We've also moved our port binding to the load balancer and out of the app service.  Our application servers no longer need to expose ports externally.  The last new bit is the setting of an environment variable to pass config options into Habitat.  You can pass values in using the variable name `HAB_NAME_OF_PACKAGE`, in our case `HAB_HAPROXY`.  By default, the HAProxy package is set to bind to *:80, but we're going to keep running it on 8080.  This allows us to pass in this config at run time without having to use `hab config apply` after the fact.

Let's bring up our new cluster with load balancing included:

```
$ docker-compose up
```
If you check the output, you should see three containers come up (redis_1, app_1, and lb_1).  We can verify using the same URL as before.

``` 
$ curl http://192.168.99.101:8080/me
Hello me!  I have seen you 1 times!<br><br>You are accessing node 1.
$ curl http://192.168.99.101:8080/me
Hello me!  I have seen you 2 times!<br><br>You are accessing node 1.
$ curl http://192.168.99.101:8080/you
Hello you!  I have seen you 1 times!<br><br>You are accessing node 1.
```
So we notice a couple of things.  Since we destroyed the previous environment that had the greeting updated to "Sup" and created a new one, we're back to our default greeting of "Hello".  We can also see that because it's a new Redis instance, our user count has started over.  

Before we worry about fixing our greeting, let's test out our shiny new load balancer.  It's working, but we currently only have one instance behind it, so we haven't really solved our problem.  Let's test out adding in some more app containers by cranking up a couple more.  Docker Compose gives us a quick way to do that:

```
$ docker-compose scale app=3                    
Creating and starting rusthelloworld_app_2 ... done
Creating and starting rusthelloworld_app_3 ... done
```
If you look in the window where you launched docker-compose initially, you should see output from app_2 and app_3 coming up:

```
app_2    | hab-sup(MN): Starting nsdavidson/rust-hello-world
app_2    | hab-sup(GS): Supervisor 172.18.0.5: 40078a1b-8a92-4318-9cbe-ca8a46a3c189
app_2    | hab-sup(GS): Census rust-hello-world.default: 858a1a82-1edb-4eb2-8b00-ec4b50253e59
app_2    | hab-sup(GS): Starting inbound gossip listener
app_2    | hab-sup(GS): Joining gossip peer at redis:9634
app_2    | hab-sup(GS): Starting outbound gossip distributor
app_2    | hab-sup(GS): Starting gossip failure detector
app_2    | hab-sup(CN): Starting census health adjuster
app_2    | hab-sup(SC): Updated config.toml
app_2    | hab-sup(TP): Restarting because the service config was updated via the census
```
You should also see some output from lb_1:

```
lb_1     | hab-sup(SC): Updated haproxy.conf
lb_1     | hab-sup(TP): Restarting because the service config was updated via the census
lb_1     | haproxy(SV): Stopping
lb_1     | hab-sup(SV): haproxy - process 59 died with signal 15
lb_1     | hab-sup(SV): haproxy - Service exited
lb_1     | haproxy(SV): Starting
```
Our load balancer immediately saw that the service group that it had a binding to had changed, regnerated its config file, and restarted.  Let's test it out:

```
$ curl http://192.168.99.101:8080/me
Hello me!  I have seen you 3 times!<br><br>You are accessing node 3.
$ curl http://192.168.99.101:8080/me
Hello me!  I have seen you 4 times!<br><br>You are accessing node 2.
$ curl http://192.168.99.101:8080/me
Hello me!  I have seen you 5 times!<br><br>You are accessing node 1.
$ curl http://192.168.99.101:8080/you
Hello you!  I have seen you 2 times!<br><br>You are accessing node 3.
$ curl http://192.168.99.101:8080/you
Hello you!  I have seen you 4 times!<br><br>You are accessing node 2.
$ curl http://192.168.99.101:8080/you
Hello you!  I have seen you 5 times!<br><br>You are accessing node 1.
```
Nice!  We can see that we're hitting all three app nodes, and the count is working properly.  Thanks to our service group binding on the load balancing service, our new nodes popped into the load balancer almost immediately!

#### Reconfigure all the things
Earlier we looked at pushing out a config change to our application, but that was for one node.  How does the process change for pushing out to N nodes?  Let's test it out.

We can't use the Habitat studio to push out our configurations this time, because Compose creates a new network that other containers can't access by default.  I've created an image that's the base Fedora 23 image with the `hab` binary installed.  We will bring up an instance of that image to interact with our new environment:

```
$ docker run -it --net=rusthelloworld_default nsdavidson/hab
```
From inside this container, we can issue the same configuration update command we used earlier, grabbing a new supervisor IP address from the Compose output (I'll use the supervisor for app_3, 172.18.0.6):

```
[root@84bfa1bcfc01 /]# echo 'greeting = "Sup"' | hab config apply --peer 172.18.0.6 rust-hello-world.default 1
» Applying configuration
↑ Applying configuration for rust-hello-world.default into ring via ["172.18.0.6:9634"]
Joining peer: 172.18.0.6:9634
Configuration applied to: 172.18.0.6:9634
★ Applied configuration.
```
So we sent the config change to app_3...but did it go anywhere else?  Let's look at the output from Compose:

```
app_3    | Writing new file from gossip: /hab/svc/rust-hello-world/gossip.toml
app_3    | hab-sup(SC): Updated config.toml
app_3    | rust-hello-world(SV): Stopping
app_3    | hab-sup(SV): rust-hello-world - process 59 died with signal 15
app_3    | hab-sup(SV): rust-hello-world - Service exited
app_3    | rust-hello-world(SV): Starting
app_3    | rust-hello-world(O): Listening on http://0.0.0.0:8080
app_3    | rust-hello-world(O): Ctrl-C to shutdown server
app_2    | Writing new file from gossip: /hab/svc/rust-hello-world/gossip.toml
app_1    | Writing new file from gossip: /hab/svc/rust-hello-world/gossip.toml
app_1    | hab-sup(SC): Updated config.toml
app_2    | hab-sup(SC): Updated config.toml
app_2    | rust-hello-world(SV): Stopping
app_1    | rust-hello-world(SV): Stopping
app_1    | hab-sup(SV): rust-hello-world - process 59 died with signal 15
app_2    | hab-sup(SV): rust-hello-world - process 60 died with signal 15
app_1    | hab-sup(SV): rust-hello-world - Service exited
app_1    | rust-hello-world(SV): Starting
app_2    | hab-sup(SV): rust-hello-world - Service exited
app_2    | rust-hello-world(SV): Starting
app_1    | rust-hello-world(O): Listening on http://0.0.0.0:8080
app_2    | rust-hello-world(O): Listening on http://0.0.0.0:8080
app_1    | rust-hello-world(O): Ctrl-C to shutdown server
app_2    | rust-hello-world(O): Ctrl-C to shutdown server
```
So the third node saw the update first, but the others immediately saw them also.  This is the gossip feature of Habitat.  All the connected peers share configuration updates.  Let's verify.

```
$ curl http://192.168.99.101:8080/you
Sup you!  I have seen you 5 times!<br><br>You are accessing node 4.
$ curl http://192.168.99.101:8080/you
Sup you!  I have seen you 5 times!<br><br>You are accessing node 6.
$ curl http://192.168.99.101:8080/you
Sup you!  I have seen you 5 times!<br><br>You are accessing node 5.
```
The node numbering is off now, but we can see that all three nodes are returning with the updated greeting value of "Sup".

### Wrap up
Our app now consists of three tiers:

- A single Redis node
- X number of application nodes that each automatically connect to the Redis node
- A single load balancer node that automatically adds new application nodes as they come up

We've covered several core concepts of Habitat, including:

- The `hab` binary
- Plans
- The Studio
- Building plans, including hooks, callbacks and configuration templates
- Habitat supervisor, including rings and service groups
- Bindings
- Configuration updates

There is a ton of information over at [https://habitat.sh](https://habitat.sh).  Please also join us in the [Habitat Slack](http://slack.habitat.sh/)!