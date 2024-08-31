FROM golang:1.21.4

# Set destination for COPY
WORKDIR /node

# Copy the source code
COPY ./ ./

# Download Go modules
RUN go mod download
RUN go mod tidy

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -o ./trustflow-node

EXPOSE 30609

# Run
CMD ["./trustflow-node"]