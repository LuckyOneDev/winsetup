Set-Alias -Name ls -Value eza
Set-Alias -Name cat -Value bat
Set-Alias -Name grep -Value rg

oh-my-posh init pwsh --config ~/darkblood.omp.json | Invoke-Expression
Set-PSReadLineOption -PredictionViewStyle ListView
