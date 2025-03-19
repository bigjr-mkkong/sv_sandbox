import numpy as np

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

