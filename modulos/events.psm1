# Módulo de Eventos: Coleta e categoriza eventos críticos do sistema.

function Get-ExplicacaoPorID($id) {
    switch ($id) {
        41      { return "[ID 41] - Desligamento inesperado detectado. Pode indicar queda de energia, travamento ou falha crítica." }
        55      { return "[ID 55] - Corrupção detectada no sistema de arquivos. Verifique integridade do disco com 'chkdsk'." }
        1001    { return "[ID 1001] - Aplicativo apresentou erro. Pode afetar softwares específicos em uso." }
        7031    { return "[ID 7031] - Serviço foi finalizado de forma inesperada. Pode causar falhas recorrentes." }
        7024    { return "[ID 7024] - Serviço terminou com erro. Verificar dependências e integridade do serviço." }
        7043    { return "[ID 7043] - Serviço não foi desligado corretamente. Pode indicar travamentos ou delays no sistema." }
        10010   { return "[ID 10010] - DCOM não respondeu no tempo esperado. Pode impactar comunicação entre aplicativos." }
        10016   { return "[ID 10016] - Permissões DCOM incorretas. Frequentemente não crítico, mas pode ser ajustado." }
        7000    { return "[ID 7000] - Serviço não foi iniciado. Pode afetar funcionalidades esperadas pelo usuário." }
        7001    { return "[ID 7001] - Serviço dependente falhou ao iniciar. Reavaliar serviços encadeados." }
        Default { return $null }
    }
}

function Get-CriticalEvents {
    # Lista de IDs de eventos que consideramos relevantes para falhas e desempenho
    $idsRelevantes = @(41, 55, 1001, 7031, 7024, 7043, 10010, 10016, 7000, 7001)

    # Coleta todos os eventos de nível 1 (Crítico) e 2 (Erro) dos últimos 7 dias
    $eventos = Get-WinEvent -FilterHashtable @{ LogName='System'; Level=@(1,2); StartTime=(Get-Date).AddDays(-7) } -ErrorAction SilentlyContinue

    $relevantes = @()
    $criticos = @()

    foreach ($e in $eventos) {
        $eventoObj = [pscustomobject]@{
            TimeCreated = $e.TimeCreated.ToString("o")
            Id = $e.Id
            LevelDisplayName = $e.LevelDisplayName
            Message = ($e.Message -split "`r`n")[0]
        }
        
        if ($idsRelevantes -contains $e.Id) {
            $relevantes += $eventoObj
        } else {
            $criticos += $eventoObj
        }
    }
    
    # Retorna um objeto que separa os eventos para análise posterior
    return [pscustomobject]@{
        TotalEventos = $eventos.Count
        EventosRelevantes = $relevantes
        EventosCriticos = $criticos
    }
}

Export-ModuleMember -Function Get-CriticalEvents, Get-ExplicacaoPorID