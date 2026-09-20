# Home Authentication Service

This service should have the Cloud Flare Tunnel as entry and put every request to a authenticate and forward proxy.

That authenticate and forward proxy should use OAuth and if properly authenticated, forward the request to the actual service depending on the domain used. So, it should be some nginx service that catches every request, checks for authentication and then forwards to the actual correct service.

The service should be in a docker compose, and the tunnel and the auth should be on the same network. The auth and forward service should furthermore be on a dedicated network where other services can be as well.

The mapping of incoming domain to other docker service on that network should be given by a read-only mounted file, so it can be updated without restarting the container. Define an appropriate format for that.

As an example, put a hello-world service in another docker-compose file (in an example-service folder).

For the OAuth, assume it is done via an office 365 account, i.e., through an entra id app. Write in the docs a tutorial on how to set it up.