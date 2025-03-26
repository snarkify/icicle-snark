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
RUN npm install -g snarkjs@0.7.5

# Set up working directory
WORKDIR /app

# Clone and build circom
RUN git clone https://github.com/iden3/circom.git && \
    cd circom && \
    cargo build --release && \
    cargo install --path circom

# Create script for verification key generation
RUN mkdir -p /app/scripts

# Files will be mounted from the host - create directories for all benchmarks
RUN mkdir -p /app/benchmark/100k/ \
    /app/benchmark/200k/ \
    /app/benchmark/400k/ \
    /app/benchmark/800k/ \
    /app/benchmark/1600k/ \
    /app/benchmark/3200k/ \
    /app/benchmark/keccak256/ \
    /app/benchmark/rsa/ \
    /app/benchmark/sha256/ \
    /app/benchmark/anon_aadhaar/ \
    /app/benchmark/keyless/

# Install dependencies for specialty circuits
RUN cd /app && \
    mkdir -p /app/benchmark/rsa && \
    cd /app/benchmark/rsa && \
    npm init -y && \
    npm install circomlib && \
    \
    mkdir -p /app/benchmark/sha256 && \
    cd /app/benchmark/sha256 && \
    npm init -y && \
    npm install circomlib && \
    \
    mkdir -p /app/benchmark/keccak256 && \
    cd /app/benchmark/keccak256 && \
    npm init -y && \
    \
    mkdir -p /app/benchmark/anon_aadhaar && \
    cd /app/benchmark/anon_aadhaar && \
    npm init -y && \
    npm install circomlib

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
# Handle phase1 special case\n\
if [ "$BENCHMARK_DIR" = "phase1" ]; then\n\
  # Only generate common powers of tau (phase 1) and exit\n\
  echo "Generating common powers of tau (phase 1) only..."\n\
  cd /app\n\
  snarkjs powersoftau new bn128 $POWER pot${POWER}_0000.ptau -v\n\
  snarkjs powersoftau contribute pot${POWER}_0000.ptau pot${POWER}_0001.ptau --name="First contribution" -v -e="random entropy"\n\
  snarkjs powersoftau prepare phase2 pot${POWER}_0001.ptau pot${POWER}_final.ptau -v\n\
  echo "Phase 1 completed. Files are in /app/"\n\
  exit 0\n\
fi\n\
\n\
# For regular benchmarks, check if common ptau files exist, otherwise generate them\n\
if [ ! -f "/app/pot${POWER}_final.ptau" ]; then\n\
  echo "Generating common powers of tau (phase 1)..."\n\
  cd /app\n\
  snarkjs powersoftau new bn128 $POWER pot${POWER}_0000.ptau -v\n\
  snarkjs powersoftau contribute pot${POWER}_0000.ptau pot${POWER}_0001.ptau --name="First contribution" -v -e="random entropy"\n\
  snarkjs powersoftau prepare phase2 pot${POWER}_0001.ptau pot${POWER}_final.ptau -v\n\
fi\n\
\n\
# Now process the specific benchmark\n\
echo "Processing benchmark: $BENCHMARK_DIR"\n\
cd /app\n\
mkdir -p $BENCHMARK_DIR\n\
cd $BENCHMARK_DIR\n\
\n\
# Copy the common ptau files if needed\n\
cp /app/pot${POWER}_0000.ptau ./pot${POWER}_0000.ptau 2>/dev/null || true\n\
cp /app/pot${POWER}_0001.ptau ./pot${POWER}_0001.ptau 2>/dev/null || true\n\
cp /app/pot${POWER}_final.ptau ./pot${POWER}_final.ptau 2>/dev/null || true\n\
\n\
# Determine the main circuit file\n\
CIRCUIT_FILE="circuit.circom"\n\
if [ ! -f "$CIRCUIT_FILE" ] && [ -f "keccak.circom" ]; then\n\
  CIRCUIT_FILE="keccak.circom"\n\
elif [ ! -f "$CIRCUIT_FILE" ] && [ -f "rsa_main.circom" ]; then\n\
  CIRCUIT_FILE="rsa_main.circom"\n\
elif [ ! -f "$CIRCUIT_FILE" ] && [ -f "sha256_512.circom" ]; then\n\
  CIRCUIT_FILE="sha256_512.circom"\n\
elif [ ! -f "$CIRCUIT_FILE" ] && [ -f "aadhaar-verifier.circom" ]; then\n\
  CIRCUIT_FILE="aadhaar-verifier.circom"\n\
fi\n\
\n\
# Install circuit dependencies if package.json exists\n\
if [ -f "package.json" ]; then\n\
  echo "Installing circuit dependencies..."\n\
  npm install\n\
fi\n\
\n\
# Compile the circuit\n\
echo "Compiling circuit: $CIRCUIT_FILE..."\n\
CIRCUIT_NAME=$(basename $CIRCUIT_FILE .circom)\n\
circom $CIRCUIT_FILE --r1cs --wasm --sym\n\
\n\
if [ $? -ne 0 ]; then\n\
  echo "Circuit compilation failed. Trying with --O1 flag..."\n\
  circom $CIRCUIT_FILE --r1cs --wasm --sym --O1\n\
fi\n\
\n\
if [ ! -f "${CIRCUIT_NAME}.r1cs" ]; then\n\
  echo "Circuit compilation failed. Exiting."\n\
  exit 1\n\
fi\n\
\n\
# Setup and contribute to the circuit-specific key (phase 2)\n\
echo "Setting up circuit key..."\n\
snarkjs groth16 setup ${CIRCUIT_NAME}.r1cs /app/pot${POWER}_final.ptau ${CIRCUIT_NAME}_0000.zkey\n\
snarkjs zkey contribute ${CIRCUIT_NAME}_0000.zkey ${CIRCUIT_NAME}_0001.zkey --name="1st Contributor Name" -v -e="more random entropy"\n\
\n\
# Export the verification key\n\
echo "Exporting verification key..."\n\
snarkjs zkey export verificationkey ${CIRCUIT_NAME}_0001.zkey verification_key.json\n\
\n\
echo "Done! Verification key generated at $BENCHMARK_DIR/verification_key.json"\n\
' > /app/scripts/generate_verification_keys.sh

RUN chmod +x /app/scripts/generate_verification_keys.sh

# Create a directory to store output files
RUN mkdir -p /output

# Create a script to run all benchmarks
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Parse arguments\n\
POWER=${1:-18}\n\
BENCHMARK=${2:-"all"}\n\
\n\
# Define all benchmark directories\n\
BENCHMARKS=("100k" "200k" "400k" "800k" "1600k" "3200k" "keccak256" "rsa" "sha256")\n\
\n\
# First, generate the common powers of tau (phase 1) only once\n\
if [ "$BENCHMARK" = "all" ] || [ "$BENCHMARK" = "phase1" ]; then\n\
  echo "Generating phase 1 powers of tau for power $POWER..."\n\
  # Run phase 1 only\n\
  /app/scripts/generate_verification_keys.sh $POWER phase1\n\
  echo "Phase 1 completed successfully"\n\
fi\n\
\n\
# Run specific benchmark or all benchmarks\n\
if [ "$BENCHMARK" = "all" ]; then\n\
  # Run all benchmarks\n\
  for bench in "${BENCHMARKS[@]}"; do\n\
    echo "Processing benchmark: $bench..."\n\
    /app/scripts/generate_verification_keys.sh $POWER "benchmark/$bench"\n\
    echo "Benchmark $bench completed successfully"\n\
  done\n\
elif [ "$BENCHMARK" != "phase1" ]; then\n\
  # Run specific benchmark\n\
  echo "Processing benchmark: $BENCHMARK..."\n\
  /app/scripts/generate_verification_keys.sh $POWER "$BENCHMARK"\n\
  echo "Benchmark $BENCHMARK completed successfully"\n\
fi\n\
\n\
echo "All operations completed successfully"\n\
' > /app/scripts/run_all_benchmarks.sh

RUN chmod +x /app/scripts/run_all_benchmarks.sh

# Set the entrypoint to the script that can run all benchmarks
ENTRYPOINT ["/bin/bash", "/app/scripts/run_all_benchmarks.sh"]
