import numpy as np

def rand_sbox_gen():
    arr = np.random.permutation(range(0, 256))
    for i in range(0, 256):
        pad1 = ""
        if i >=0 and i <= 9:
            pad1 = "  "
        elif i >=10 and i <= 99:
            pad1 = " "
        else:
            pad1 = ""

        pad2 = ""
        if arr[i] >=0 and arr[i] <= 9:
            pad2 = "  "
        elif arr[i] >=10 and arr[i] <= 99:
            pad2 = " "
        else:
            pad2 = ""

        strr = "8'd"+str(i)+pad1 + ": data_o=" + "8'd"+str(arr[i]) + pad2+ ";"
        print(strr)
        strr = ""

# This sbox was generated by rand_sbox_gen()
# Your provided random S-Box
sbox = [
    6,212,112,111,250,139,166,164,203,53,54,87,199,84,10,248,96,127,148,97,123,14,219,17,110,114,
    15,104,136,192,43,177,62,83,22,221,181,72,173,39,222,201,4,13,229,244,41,7,191,19,51,176,20,
    0,73,217,3,159,30,82,187,80,35,246,146,37,208,211,243,79,101,44,130,76,179,66,120,235,224,140,
    52,108,197,216,98,91,220,71,150,18,143,137,124,149,190,213,38,47,151,90,26,69,141,31,77,157,
    215,132,171,28,180,240,113,16,1,184,133,254,194,102,29,128,153,119,236,178,75,161,175,40,95,
    245,209,117,115,61,135,156,93,196,238,233,169,12,144,57,70,21,162,27,170,34,247,230,50,64,
    134,68,206,33,228,195,60,145,147,103,23,8,198,239,86,122,99,105,78,106,218,94,42,188,24,185,
    154,11,118,56,107,36,207,160,109,25,48,65,158,85,89,59,67,138,172,251,223,234,214,252,74,58,
    165,202,204,167,237,129,155,88,152,241,55,182,200,249,49,232,32,46,2,142,183,174,231,168,9,
    210,227,186,226,131,125,63,225,121,116,5,242,45,81,126,163,189,193,205,92,100,255,253
]

def xtime(x):
    """ GF(2^4) multiply by 2 """
    return ((x << 1) & 0xF) ^ (0x3 & -(x >> 3))

def gf_mult(x, factor):
    """ Multiply x by a constant in GF(2^4) """
    if factor == 1:
        return x
    elif factor == 2:
        return xtime(x)
    elif factor == 9:
        return xtime(xtime(xtime(x))) ^ x
    elif factor == 11:
        return xtime(xtime(xtime(x))) ^ xtime(x) ^ x
    else:
        raise ValueError("Unsupported multiplication factor in GF(2^4)")

def inverse_mix_columns(state):
    """ Reverse AES MixColumns transformation for 4x4 bit matrix stored in 16-bit integer """
    # Extract nibbles (4-bit segments)
    s = [(state >> (4 * i)) & 0xF for i in range(4)]

    # Apply inverse MixColumns matrix multiplication
    inv_mixed = [0] * 4
    inv_mixed[0] = gf_mult(s[0], 9)  ^ gf_mult(s[1], 2)  ^ gf_mult(s[2], 2)  ^ gf_mult(s[3], 11)
    inv_mixed[1] = gf_mult(s[0], 11) ^ gf_mult(s[1], 9)  ^ gf_mult(s[2], 2)  ^ gf_mult(s[3], 2)
    inv_mixed[2] = gf_mult(s[0], 2)  ^ gf_mult(s[1], 11) ^ gf_mult(s[2], 9)  ^ gf_mult(s[3], 2)
    inv_mixed[3] = gf_mult(s[0], 2)  ^ gf_mult(s[1], 2)  ^ gf_mult(s[2], 11) ^ gf_mult(s[3], 9)

    # Pack transformed nibbles back into a 16-bit integer
    return sum(inv_mixed[i] << (4 * i) for i in range(4))


# --- Encryption Functions ---

def sbox_substitution(state):
    """ Apply sbox substitution to 2-byte input """
    high = state >> 8
    low = state & 0xFF
    return (sbox[high] << 8) | sbox[low]

def shift_rows(state):
    """ Perform a simple bitwise left rotation on nibbles like AES ShiftRows """
    s = [(state >> (4 * i)) & 0xF for i in range(4)]
    rotated = [
        s[0],
        ((s[1] >> 1) | ((s[1] & 0x1) << 3)),
        ((s[2] >> 2) | ((s[2] & 0x3) << 2)),
        ((s[3] >> 3) | ((s[3] & 0x7) << 1))
    ]
    return sum(rotated[i] << (4 * i) for i in range(4))

def xtime(x):
    """ GF(2^4) multiply by 2 """
    return ((x << 1) & 0xF) ^ (0x3 & -(x >> 3))

def mix_columns(state):
    """ MixColumns for 4 nibbles """
    s = [(state >> (4 * i)) & 0xF for i in range(4)]
    m = [0] * 4
    m[0] = xtime(s[0]) ^ (xtime(s[1]) ^ s[1]) ^ s[2] ^ s[3]
    m[1] = s[0] ^ xtime(s[1]) ^ (xtime(s[2]) ^ s[2]) ^ s[3]
    m[2] = s[0] ^ s[1] ^ xtime(s[2]) ^ (xtime(s[3]) ^ s[3])
    m[3] = (xtime(s[0]) ^ s[0]) ^ s[1] ^ s[2] ^ xtime(s[3])
    return sum(m[i] << (4 * i) for i in range(4))

def one_round_aes_encrypt(ptext, key):
    """ One round AES: AddRoundKey -> SBox -> ShiftRows -> MixColumns """
    s1 = ptext ^ key
    s2 = sbox_substitution(s1)
    s3 = shift_rows(s2)
    s4 = mix_columns(s3)
    return s4

# --- Inverse S-Box Generation ---
def inverse_sbox_gen(sbox):
    inv = [0] * 256
    for i, val in enumerate(sbox):
        inv[val] = i
    return inv

inv_sbox = inverse_sbox_gen(sbox)

# --- Inverse Functions ---


def inverse_shift_rows(state):
    """ Reverse ShiftRows transformation """
    s = [(state >> (4 * i)) & 0xF for i in range(4)]
    rotated = [
        s[0],
        ((s[1] << 1) & 0xF) | (s[1] >> 3),
        ((s[2] << 2) & 0xF) | (s[2] >> 2),
        ((s[3] << 3) & 0xF) | (s[3] >> 1)
    ]
    return sum(rotated[i] << (4 * i) for i in range(4))

def inverse_sbox_substitution(state):
    high = state >> 8
    low = state & 0xFF
    return (inv_sbox[high] << 8) | inv_sbox[low]

def one_round_aes_decrypt(ciphertext, key):
    s3 = inverse_mix_columns(ciphertext)

    s2 = inverse_shift_rows(s3)
    s1 = inverse_sbox_substitution(s2)
    ptext = s1 ^ key
    return ptext


ptext = 1234
key = 13
cip = one_round_aes_encrypt(ptext, key)

dec_cip = one_round_aes_encrypt(cip, key)

print(cip, dec_cip)
