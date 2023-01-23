# gitlab-sandwich

An AWS NLB/ALB sandwich designed for a standalone GitLab instance

## How does this work?

A standalone GitLab instance within AWS needs these tcp ports passed thru:

- tcp/22 - for SSH to the GitLab instance
- tcp/80 - for standard HTTP (we simply want to redirect this to HTTPS)
- tcp/443 - for HTTPS (both browsing and git functionality)

An NLB will pass the tcp ports through and can even be set for TLS termination (so you can use your SSL/TLS certificate from ACM). NLBs cannot perform actions at the HTTP/HTTPS protocol level

An ALB can be used for the HTTP to HTTPS redirect

## What is not included within this?

None of the code used to build out the actual GitLab instance. There are multiple examples to choose from online.

## How can I use the included docker-compose?

The included docker-compose allows you to use a standard Terraform docker container to run all terraform functionality (thus not requiring to install/run terraform or tfenv on your system directly)

To use, simply use the command:

```
docker-compose run terra
```

This will start up the container and drop the user into an interactive shell on the container.

The volume mounts will allow you to:

- mount AWS credentials already on the host system (read-only)
- mount a local directory so that all your working terraform files will be available in the container

## Some things that are not yet worked out

1. Sometimes terraform requires an apply to be performed more than once because of an order-of-operations problem. This problem will show up as a message like `If the target type is ALB, the target must have at least one listener...`

1. Related to the above, sometimes a terraform destroy will need to be run twice

1. The port between the NLB and ALB cannot be the original port for the NLB ingress. This may be an architecture limitation - but I don't know that yet.
