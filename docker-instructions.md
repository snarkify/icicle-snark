# Docker Instructions for Icicle-SNARK

This docker setup provides an environment for compiling circom circuits and generating verification keys.

## Building the Docker Image

From the root of the repository, run:

```bash
docker build -t icicle-snark .
```

## Usage

The Docker image accepts two parameters:
1. The power of tau (default: 18)
2. The benchmark directory to use (default: "benchmark/100k")

### Basic Usage with Default Parameters

```bash
docker run -v $(pwd)/benchmark:/app/benchmark icicle-snark
```

This will run with power=18 and use the benchmark/100k directory.

### Specify a Different Power of Tau

```bash
docker run -v $(pwd)/benchmark:/app/benchmark icicle-snark 20
```

This will run with power=20 and use the benchmark/100k directory.

### Specify a Different Benchmark Directory

```bash
docker run -v $(pwd)/benchmark:/app/benchmark icicle-snark 18 "benchmark/200k"
```

This will run with power=18 and use the benchmark/200k directory.

## Output

The script will generate the following files in the specified benchmark directory:
- Powers of tau files: `pot{POWER}_0000.ptau`, `pot{POWER}_0001.ptau`, `pot{POWER}_final.ptau`
- Circuit keys: `circuit_0000.zkey`, `circuit_0001.zkey`
- Verification key: `verification_key.json`

## Note

For proper execution, ensure the specified benchmark directory contains:
1. `circuit.circom` - The circuit file to compile
2. `input.json` - Input values for the circuit

The verification keys will be generated in the same directory.
