# Authenticate

## Create service principal for python access

```
az ad sp create-for-rbac --name jenkins-user --role Contributor

```

## Login using service principal

```
# username = appId, password=password, tenant=tenant
# az login --service-principal -u "$CLIENT_ID" -p "$CLIENT_SERCRET" --tenant "$TENANT_ID" # not needed for switch
```
## Environment variables needed for switch:

```
export AZURE_CLIENT_ID='appId' # see above
export AZURE_CLIENT_SECRET='password' # see above
export AZURE_TENANT_ID='tenant' # see above
export AZURE_SUBSCRIPTION_ID='subscription-id' # can be found via 'az account list'
```


