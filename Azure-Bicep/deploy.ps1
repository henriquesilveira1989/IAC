
param($location, $project, $envrionment)

$resourceGroup = 'rg-'+ $project + '-' + $envrionment

az group create --location 'useast1' --name $resourceGroup 

az deployment group create -f ./main.json -g $resourceGroup --parameters project=$project `
                                                                        env=$envrionment `
                                                                        location=$location `



                                                        





