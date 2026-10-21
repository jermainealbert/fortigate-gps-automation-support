$PasswordPath = "D:\FortiGateGPS\FortiGateSSHPassword.dat"

$SecurePassword = Get-Content $PasswordPath | ConvertTo-SecureString

$BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)

try {
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
}