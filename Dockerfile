# Stage 1 — build
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY app/go.mod ./
RUN go mod download
COPY app/ .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

# Stage 2 — distroless final image
FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY --from=builder /app/server .
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/server"]
