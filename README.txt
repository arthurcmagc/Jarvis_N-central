# Jarvis - Assistente de Diagnóstico e Automação Local

## Visão Geral

O Jarvis é um assistente inteligente de diagnóstico e automação desenvolvido em PowerShell.
Sua principal missão é atuar como um "agente local" que monitora, diagnostica e reage de forma autônoma a problemas em 
máquinas locais.

Diferente de um simples script, o Jarvis atua como o ponto de partida de um fluxo de trabalho.
Ele não apenas encontra problemas, mas também toma decisões e se comunica com plataformas de automação (como o n8n) 
para acionar alertas, abrir tickets ou notificar equipes, transformando o suporte técnico reativo em proativo.

## Funcionalidades da Versão Atual (v2)

**Diagnóstico de Sistema:** Realiza uma análise completa de hardware (RAM, CPU, discos), 
eventos do sistema e status de rede.

**Pontuação Geral:** Gera uma pontuação de saúde geral em tempo real, fornecendo uma visão clara do status da máquina.

**Automação Inteligente:** Se a pontuação de saúde estiver abaixo de um limite pré-definido, 
o Jarvis envia automaticamente um webhook para o n8n, disparando ações automatizadas.

**Geração de Relatório:** Salva o diagnóstico completo em um arquivo JSON para análise posterior.

**Correções Rápidas:** Oferece opções para executar rotinas de correção automática, como o `sfc /scannow`.

## Requisitos

-   Windows 10 ou 11
-   PowerShell 5.1 ou mais recente

## Como Usar

1.  Abra o PowerShell como Administrador.
2.  Navegue até a pasta raiz do projeto Jarvis.
3.  Execute o arquivo `menu.ps1`.
4.  O menu interativo será exibido, permitindo que você escolha a opção desejada.

**Para Testar a Automação:**

1.  Certifique-se de que o URL do seu webhook no arquivo `config.json` está correto.
2.  Ajuste temporariamente o valor de `health_score_threshold` para um número acima da sua pontuação atual 
(por exemplo, `90`).
3.  Inicie o workflow no n8n.
4.  Execute o diagnóstico no Jarvis e observe o alerta ser disparado.

## Próximos Passos

A visão de futuro para o Jarvis inclui a expansão de seus módulos de diagnóstico 
(como inventário de software e segurança).
E a integração com modelos de IA diretamente do n8n para análises e recomendações ainda mais inteligentes.