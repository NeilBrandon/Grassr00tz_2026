# FrostyGoop

This folder contains the Docker configuration for the FrostyGoop demo environment.

## Prerequisites

- Docker Desktop installed and running
- `docker-compose` available on your path

## Start the environment

From the `FrostyGoop/` directory, run:

```powershell
docker-compose up -d
```

This starts:

- `ignition_gr` — Ignition gateway on `http://localhost:8088`
- `netshoot_gr` — Netshoot troubleshooting container

## Jump into the netshoot container

Use the following command to open an interactive shell inside `netshoot_gr`:

```powershell
docker exec -it netshoot_gr bash
```

Once inside, you can run network tools like `curl`, `tcpdump`, `dig`, `ip`, and other troubleshooting utilities.

If you want to use the mounted `./netshoot` directory from the host, it is available at `/root` inside the container.

## Stop the environment

From the `FrostyGoop/` directory, run:

```powershell
docker-compose down
```

This stops and removes the containers created by the compose file.

## Notes

- The `netshoot_gr` container is configured to stay running with `tail -f /dev/null`, so you can `exec` into it at any time.
- If you need to restart the environment, use `docker-compose down` followed by `docker-compose up -d`.
