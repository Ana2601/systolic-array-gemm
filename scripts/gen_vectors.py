#!/usr/bin/env python3
"""Random INT8 GEMM tiles and their exact int32 results (pure-Python golden model).

Line format: K, then A row-major (S*K), B row-major (K*S), C row-major (S*S); hex, two's complement.
"""
import random
import sys


def main(s, kmax, n, path, seed=1):
    rng = random.Random(seed)
    ks = [1, 2, s, kmax, kmax - 1] + [rng.randrange(1, kmax + 1) for _ in range(n - 5)]
    with open(path, "w") as f:
        for t, k in enumerate(ks):
            mode = t % 4
            def val():
                if mode == 0:
                    return rng.choice([-128, 127])          # extremes: worst-case accumulation
                if mode == 1:
                    return rng.randrange(-4, 5)             # small / sparse
                return rng.randrange(-128, 128)
            a = [[val() for _ in range(k)] for _ in range(s)]
            b = [[val() for _ in range(s)] for _ in range(k)]
            c = [[sum(a[i][x] * b[x][j] for x in range(k)) for j in range(s)] for i in range(s)]
            fields = [f"{k:x}"]
            fields += [f"{v & 0xFF:02x}" for row in a for v in row]
            fields += [f"{v & 0xFF:02x}" for row in b for v in row]
            fields += [f"{v & 0xFFFFFFFF:08x}" for row in c for v in row]
            f.write(" ".join(fields) + "\n")
    print(f"wrote {len(ks)} GEMM tiles ({s}x{s}, K up to {kmax}) to {path}")


if __name__ == "__main__":
    main(int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4])
