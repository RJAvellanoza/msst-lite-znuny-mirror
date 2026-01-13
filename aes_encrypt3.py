import base64
import json
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad
from Crypto.Random import get_random_bytes

def encrypt_data(plaintext, key):
    # Generate a random initialization vector (IV)
    iv = get_random_bytes(16)  # AES block size is 16 bytes

    # Pad the plaintext to be a multiple of 16 bytes
    padded_plaintext = pad(plaintext, AES.block_size)

    # Create a new AES cipher object with CBC mode
    cipher = AES.new(key, AES.MODE_CBC, iv)

    # Encrypt the plaintext
    ciphertext = cipher.encrypt(padded_plaintext)

    return iv, ciphertext

def write_license_file(iv, ciphertext, filename):
    # Write the IV and ciphertext to a file with a .lic extension
    with open(filename, 'wb') as file:
        file.write(iv + ciphertext)

##########################base64-encoding########################################
def decrypt_app_encrypted_key(encrypted_key_b64, key):
    """
    Decrypts the base64-encoded (IV + ciphertext) output from app.py.
    Returns the decrypted plaintext as a string.
    """
    # Decode the base64 string to get raw bytes
    encrypted_bytes = base64.b64decode(encrypted_key_b64)
    iv = encrypted_bytes[:16]
    ciphertext = encrypted_bytes[16:]

    # Create AES cipher and decrypt
    cipher = AES.new(key, AES.MODE_CBC, iv)
    padded_plaintext = cipher.decrypt(ciphertext)
    plaintext = unpad(padded_plaintext, AES.block_size)

    return plaintext.decode('utf-8')

def read_and_decrypt_license_file_app(filename, key):
    # Read the base64-encoded string from the .lic file
    with open(filename, 'r') as file:
        encrypted_key_b64 = file.read().strip()

    decrypted_plaintext = decrypt_app_encrypted_key(encrypted_key_b64, key)
    return decrypted_plaintext
###################################################################################

############################old-binary-encoding########################################
def read_and_decrypt_license_file(filename, key):
    # Read the IV and ciphertext from the .lic file
    with open(filename, 'rb') as file:
        iv = file.read(16)  # Read the first 16 bytes as the IV
        ciphertext = file.read().strip()  # Read the rest as the ciphertext

    # Create a new AES cipher object with the same key and IV
    cipher = AES.new(key, AES.MODE_CBC, iv)

    # Decrypt the ciphertext
    decrypted_padded_plaintext = cipher.decrypt(ciphertext)

    # Unpad the decrypted plaintext
    decrypted_plaintext = unpad(decrypted_padded_plaintext, AES.block_size)

    return decrypted_plaintext
#########################################################################################



# Example usage
if __name__ == "__main__":
    # old version license data
    json1 = {"msstLiteLicense":{"UID":"AS_90001470_02FD1_NOC33331","contractCompany":"NEXUSCORPGROUP SDN BHD","endCustomer":"MY ROYAL MALAYSIA POLICE","contractNumber":"1036990390","macAddress":"6C-0B-5E-EE-B7-40","startDate":"2025/05/01","endDate":"2030/05/01"}}
    json1 = {
        "msstLiteLicense": {
        "UID": "CAM7519W",
        "contractCompany": "CHICAGO OFFICE OF EMERGENCY MANAGEMENT AND COMM",
        "endCustomer": "CHICAGO OFFICE OF EMERGENCY MGMT AND COMMS, CITY OF_ESS",
        "contractNumber":"1036907402",
        "macAddress":"bc:24:11:c6:9c:8d",
        "startDate": "2025/07/21",
        "endDate": "2030/07/21"
        }
    }

    plaintext = json.dumps(json1).encode('utf-8')
    license_filename = 'license/{}-{}-{}-{}.lic'.format(json1["msstLiteLicense"]["endCustomer"],json1["msstLiteLicense"]["UID"],json1["msstLiteLicense"]["macAddress"].replace(":", "").replace("-", ""),json1["msstLiteLicense"]["endDate"].replace("/", ""))
    license_filename = license_filename.replace(" ", "").replace(",", "")
    # AES key
    key=b'\xfc\xfcwn\x08\xe2\x88\xb9<\xcb.\x14>\xacH;\x7f\xc1\xe8\xd4\xe2e\x870\xcai\x16\x0e\x12+\t\xd0'

    # # Generate a random key (16 bytes for AES-128)
    # key = get_random_bytes(32)
    # print("key:", key)

    # Encrypt the data
    iv, encrypted_data = encrypt_data(plaintext, key)

    # #uncomment this to create license file
    # # Write the encrypted data to a .lic file
    # write_license_file(iv, encrypted_data, license_filename)
    # print("Encrypted data written to license.lic")

    # Read back the .lic file and decrypt
    license_filename = "license/{}.lic".format("testrenewal_123pri_20250715")
    # old license decrypt (binary encoding)
    # decrypted_data = read_and_decrypt_license_file(license_filename, key)
    # print("Decrypted data:", decrypted_data.decode())

    # new license decrypt (base64 encoding)
    decrypted_data = read_and_decrypt_license_file_app(license_filename, key)
    print("Decrypted data:", decrypted_data)
