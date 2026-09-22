<#
    KGN4j - quick environment check before you start.
    Verifies Node, npm, git, the Neo4j HTTP endpoint, the Bolt port and
    the PostgreSQL port. Reports, changes nothing.
#>
$ErrorActionPreference = 'Continue'

function Test-Port($hostname, $port, $label) {
    $ok = Test-NetConnection -ComputerName $hostname -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($ok) { Write-Host ("  OK       {0} ({1}:{2})" -f $label, $hostname, $port) -ForegroundColor Green }
    else     { Write-Host ("  MISSING  {0} ({1}:{2}) - not listening" -f $label, $hostname, $port) -ForegroundColor Red }
}

Write-Host 'Tooling' -ForegroundColor Cyan
foreach ($c in 'node','npm','git') {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { Write-Host ("  OK       {0} {1}" -f $c, (& $c --version)) -ForegroundColor Green }
    else      { Write-Host ("  MISSING  {0}" -f $c) -ForegroundColor Red }
}

Write-Host ''
Write-Host 'Services' -ForegroundColor Cyan
Test-Port 'localhost' 5432 'PostgreSQL'
Test-Port 'localhost' 7474 'Neo4j HTTP / Browser'
Test-Port 'localhost' 7687 'Neo4j Bolt (NeoDash connects here)'
Test-Port 'localhost' 3000 'NeoDash dev server'

Write-Host ''
Write-Host 'Reminder: the PostgreSQL JDBC jar must be in <NEO4J_HOME>\plugins' -ForegroundColor Yellow
Write-Host 'alongside apoc-*-core.jar, and Neo4j restarted after adding it.' -ForegroundColor Yellow
