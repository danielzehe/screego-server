# Development

Screego requires:

- Go 1.15+
- Node 13.x
- Yarn 9+

## Setup

### Clone Repository

Clone screego/server source from git:

```bash
$ git clone https://github.com/screego/server.git && cd server
```

### GOPATH

If you are in GOPATH, enable [go modules](https://github.com/golang/go/wiki/Modules) explicitly:

```bash
$ export GO111MODULE=on
```

### Download Dependencies:

```bash
# Server
$ go mod download
# UI
$ (cd ui && yarn install)
```

## Start / Linting

### Backend

Create a file named `screego.config.development.local` inside the screego folder with the content:

```ini
SCREEGO_EXTERNAL_IP=YOURIP
```

and replace `YOURIP` with your external ip.

Start the server in development mode.

```bash
$ go run . serve
```

The backend is available on [http://localhost:5050](http://localhost:5050)

?> When accessing `localhost:5050` it is normal that there are panics with `no such file or directory`.
The UI will be started separately.

### Frontend

Start the UI development server.

_Commands must be executed inside the ui directory._

```bash
$ yarn start
```

Open [http://localhost:3000](http://localhost:3000) inside your favorite browser.

### Lint

Screego uses [golangci-lint](https://github.com/golangci/golangci-lint) for linting.

After installation you can check the source code with:

```bash
$ golangci-lint run
```

## Build

1. [Setup](#setup)

1. Build the UI

   ```bash
   $ (cd ui && yarn build)
   ```

1. Build the binary
   ```bash
   go build -ldflags "-X main.version=$(git describe --tags HEAD) -X main.mode=prod" -o screego ./main.go
   ```

## Local Multi-Arch Docker Build

Build and optionally push multi-platform images locally without GitHub Actions.

### Files

- `Dockerfile.multiarch`
- `scripts/build-multiarch-image.sh`

### Push to your registry

```bash
./scripts/build-multiarch-image.sh \
  --version 1.12.2b \
  --repo registry.example.com/screego \
  --tag 1.12.2b \
  --tag latest
```

### Build without push

Single platform (loads into local Docker daemon):

```bash
./scripts/build-multiarch-image.sh \
  --repo registry.example.com/screego \
  --tag dev \
  --no-push \
  --platforms linux/amd64
```

Multi-platform (exports OCI archive):

```bash
./scripts/build-multiarch-image.sh \
  --repo registry.example.com/screego \
  --tag dev \
  --no-push
```

Default OCI output path:

```text
dist/docker/<repo>_<tag>.oci.tar
```
