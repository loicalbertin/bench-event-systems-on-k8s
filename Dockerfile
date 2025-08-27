# Stage 1: Build the Go application
FROM golang:1.25 AS builder

# Set the Current Working Directory inside the container
WORKDIR /app

# Copy go mod and sum files
COPY go.mod go.sum ./

# Download all dependencies. Dependencies will be cached if the go.mod and go.sum files are not changed
RUN go mod download

# Copy the source from the current directory to the Working Directory inside the container
COPY *.go .

# Build the Go app
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bench .

# Stage 2: Create a minimal image using distroless
FROM gcr.io/distroless/base-debian12:nonroot

# Copy the binary from the builder stage
COPY --from=builder /app/bench /app/bench

# Command to run the executable
ENTRYPOINT ["/app/bench"]