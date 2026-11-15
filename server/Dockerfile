FROM golang:1.26-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
ARG COMMIT=none
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath \
    -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
    -o /out/api ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/api /api
ENV PORT=8080 METRICS_PORT=9090
EXPOSE 8080 9090
USER nonroot:nonroot
ENTRYPOINT ["/api"]
