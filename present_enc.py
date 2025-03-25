# PRESENT Cipher - Lightweight Block Cipher
from typing import List

# 4-bit PRESENT S-Box
PRESENT_SBOX = [
    0xC, 0x5, 0x6, 0xB,
    0x9, 0x0, 0xA, 0xF,
    0xD, 0x1, 0x8, 0x4,
    0x7, 0x3, 0xE, 0x2
]

# Inverse S-Box
PRESENT_SBOX_INV = [
    0x5, 0x9, 0xF, 0xD,
    0xB, 0x1, 0x2, 0xC,
    0xA, 0x4, 0x6, 0x3,
    0x0, 0x8, 0xE, 0x7
]

# Bit permutation layer
PRESENT_PBOX = [
    0, 16, 32, 48,  1, 17, 33, 49,
    2, 18, 34, 50,  3, 19, 35, 51,
    4, 20, 36, 52,  5, 21, 37, 53,
    6, 22, 38, 54,  7, 23, 39, 55,
    8, 24, 40, 56,  9, 25, 41, 57,
   10, 26, 42, 58, 11, 27, 43, 59,
   12, 28, 44, 60, 13, 29, 45, 61,
   14, 30, 46, 62, 15, 31, 47, 63
]

PRESENT_PBOX_INV = [0]*64
for i, pos in enumerate(PRESENT_PBOX):
    PRESENT_PBOX_INV[pos] = i

def sbox_layer(state: int) -> int:
    return sum(PRESENT_SBOX[(state >> (4*i)) & 0xF] << (4*i) for i in range(16))

def sbox_layer_inv(state: int) -> int:
    return sum(PRESENT_SBOX_INV[(state >> (4*i)) & 0xF] << (4*i) for i in range(16))

def pbox_layer(state: int) -> int:
    out = 0
    for i in range(64):
        bit = (state >> i) & 1
        out |= bit << PRESENT_PBOX[i]
    return out

def pbox_layer_inv(state: int) -> int:
    out = 0
    for i in range(64):
        bit = (state >> i) & 1
        out |= bit << PRESENT_PBOX_INV[i]
    return out

def generate_round_keys(master_key: int, rounds: int = 32) -> List[int]:
    round_keys = []
    key = master_key & ((1 << 80) - 1)
    for i in range(rounds):
        round_keys.append(key >> 16)
        # Rotate
        key = ((key << 61) | (key >> 19)) & ((1 << 80) - 1)
        # S-box
        sbox_input = (key >> 76) & 0xF
        key &= ~(0xF << 76)
        key |= PRESENT_SBOX[sbox_input] << 76
        # XOR round counter
        key ^= (i + 1) << 15
    return round_keys

def present_encrypt(plaintext: int, key: int, rounds: int = 31) -> int:
    state = plaintext & ((1 << 64) - 1)
    round_keys = generate_round_keys(key, rounds + 1)
    for i in range(rounds):
        state ^= round_keys[i]
        state = sbox_layer(state)
        state = pbox_layer(state)
    state ^= round_keys[-1]
    return state

def present_decrypt(ciphertext: int, key: int, rounds: int = 31) -> int:
    state = ciphertext & ((1 << 64) - 1)
    round_keys = generate_round_keys(key, rounds + 1)
    state ^= round_keys[-1]
    for i in reversed(range(rounds)):
        state = pbox_layer_inv(state)
        state = sbox_layer_inv(state)
        state ^= round_keys[i]
    return state

# Example usage:
plaintext = 0x0123456789ABCDEF
key = 0x00000000000000000000FFFF
ciphertext = present_encrypt(plaintext, key)
decrypted = present_decrypt(ciphertext, key)
assert decrypted == plaintext

