# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

COPY go.mod ./
COPY *.go ./

RUN go mod tidy
RUN go mod download

RUN CGO_ENABLED=0 GOOS=linux go build -o /auth-service .

# Runtime stage
FROM alpine:3.19

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /auth-service .

EXPOSE 8001

CMD ["./auth-service"]
