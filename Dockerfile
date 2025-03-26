FROM ubuntu:22.04

# Avoid prompts during package installation
ARG DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    libssl-dev \
    pkg-config \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 18.x
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install snarkjs globally
RUN npm install -g snarkjs@0.5.0

# Set up working directory
WORKDIR /app

# Clone and build circom
RUN git clone https://github.com/iden3/circom.git && \
    cd circom && \
    cargo build --release && \
    cargo install --path circom

# Create script for verification key generation
RUN mkdir -p /app/scripts

# Files will be mounted from the host
RUN mkdir -p /app/benchmark/100k/

# Script to generate verification keys
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Parse arguments\n\
POWER=${1:-18}\n\
BENCHMARK_DIR=${2:-"benchmark/100k"}\n\
\n\
echo "Generating verification keys with power: $POWER"\n\
\n\
cd /app\n\
mkdir -p $BENCHMARK_DIR\n\
cd $BENCHMARK_DIR\n\
\n\
# Compile the circuit\n\
echo "Compiling circuit..."\n\
circom circuit.circom --r1cs --wasm --sym\n\
\n\
# Generate powers of tau\n\
echo "Generating powers of tau..."\n\
snarkjs powersoftau new bn128 $POWER pot${POWER}_0000.ptau -v\n\
snarkjs powersoftau contribute pot${POWER}_0000.ptau pot${POWER}_0001.ptau --name="First contribution" -v -e="random entropy"\n\
snarkjs powersoftau prepare phase2 pot${POWER}_0001.ptau pot${POWER}_final.ptau -v\n\
\n\
# Setup and contribute to the circuit-specific key\n\
echo "Setting up circuit key..."\n\
snarkjs groth16 setup circuit.r1cs pot${POWER}_final.ptau circuit_0000.zkey\n\
snarkjs zkey contribute circuit_0000.zkey circuit_0001.zkey --name="1st Contributor Name" -v -e="more random entropy"\n\
\n\
# Export the verification key\n\
echo "Exporting verification key..."\n\
snarkjs zkey export verificationkey circuit_0001.zkey verification_key.json\n\
\n\
echo "Done! Verification key generated at $BENCHMARK_DIR/verification_key.json"\n\
' > /app/scripts/generate_verification_keys.sh

RUN chmod +x /app/scripts/generate_verification_keys.sh

# Create a directory to store output files
RUN mkdir -p /output

# Set the entrypoint to the script
ENTRYPOINT ["/bin/bash", "/app/scripts/generate_verification_keys.sh"]
