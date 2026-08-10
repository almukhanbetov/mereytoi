# ---- Build stage ----
FROM golang:1.25-alpine AS builder
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/server ./cmd/server

# ---- Runtime stage ----
FROM alpine:3.20
# ffmpeg transcodes uploaded videos to H.264/AAC — iPhone recordings default
# to HEVC, which most browsers can't decode natively.
RUN apk add --no-cache ca-certificates ffmpeg
WORKDIR /app

COPY --from=builder /out/server ./server
RUN mkdir -p /app/uploads

EXPOSE 8090
ENTRYPOINT ["./server"]
