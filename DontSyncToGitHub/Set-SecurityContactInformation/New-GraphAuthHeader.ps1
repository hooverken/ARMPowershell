# Returns a hashtable which can be used as the headers for a REST API request

$header = @{}
$header.Add("Content-Type","application/json")
$header.Add("Authorization",(Get-AzBearerToken))

$header
