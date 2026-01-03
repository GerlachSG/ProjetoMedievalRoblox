--[[
    EntradaJogador.client.lua
    
    Script local que captura inputs do jogador e envia ações para o servidor.
    Responsável apenas por:
    - Detectar inputs (mouse, teclado)
    - Enviar RemoteEvents com a ação desejada
    - Gerenciar estado de teclas pressionadas
    
    NÃO gerencia animações, estados ou lógica de combate.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _ContextActionService = game:GetService("ContextActionService") -- Reservado para uso futuro

local player = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════
-- REMOTE EVENTS
-- ═══════════════════════════════════════════════════════════════════

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TentarAcao = Remotos:WaitForChild("TentarAcao")

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE INPUTS
-- ═══════════════════════════════════════════════════════════════════

local Configuracao = {
	-- Tempo para considerar ataque pesado (segurar M1)
	TempoCarregarPesado = 0.2,

	-- Cooldowns
	CooldownDefesa = 0.5, -- Cooldown de 0.5 segundos para defesa

	-- Teclas
	TeclaAgachar = Enum.KeyCode.C,
	TeclaCorrer = Enum.KeyCode.LeftShift,
	TeclaQuebrarDefesa = Enum.KeyCode.G,
}

-- ═══════════════════════════════════════════════════════════════════
-- ESTADO LOCAL DE INPUTS
-- ═══════════════════════════════════════════════════════════════════

local estadoInput = {
	mouse1Pressionado = false,
	mouse2Pressionado = false,
	tempoMouse1 = 0,
	agachadoAtivo = false,
	correndoAtivo = false,
	ultimaDefesa = 0,
}

-- Estado de equipamento
local toolAtualEquipado = nil -- Referência ao Tool atualmente equipado
local ultimoToolProcessado = nil -- Último tool que iniciou equip/desequip (para rastrear toggle)
local direcaoEquip = 0 -- 1 = equipando, -1 = desequipando, 0 = nenhum

-- ═══════════════════════════════════════════════════════════════════
-- CALLBACKS GLOBAIS
-- ═══════════════════════════════════════════════════════════════════

--- Callback chamado pelo ControladorEstado quando a animação de equipar/desequipar termina
--- Reseta o estado de direção de equip
--- @param direcaoFinal number 1 se terminou equipando, -1 se terminou desequipando
_G.OnEquipAnimacaoTerminou = function(direcaoFinal: number)
	print("[EntradaJogador] Animação de equip terminou. Direção final:", direcaoFinal)
	direcaoEquip = 0

	-- Se terminou desequipando, limpa referências
	if direcaoFinal == -1 then
		ultimoToolProcessado = nil
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE AÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Envia ação para o servidor
local function EnviarAcao(acao: string, dados: any?)
	TentarAcao:FireServer(acao, dados)
end

--- Processa clique do mouse 1 (ataque)
--- No sistema de combo por marcadores:
--- - Se há combo ativo (janela ou animação), tenta marcar continuação
--- - Caso contrário, envia novo ataque
local function ProcessarMouse1Pressionado()
	estadoInput.mouse1Pressionado = true
	estadoInput.tempoMouse1 = tick()

	-- Verifica se há combo ativo (função exposta pelo ControladorEstado)
	local comboAtivo = _G.EstaComboAtivo and _G.EstaComboAtivo()
	local janelaAtiva = _G.EstaJanelaComboAtiva and _G.EstaJanelaComboAtiva()

	if comboAtivo or janelaAtiva then
		-- Combo ativo - marca para continuar
		if _G.MarcarContinuarCombo then
			local marcou = _G.MarcarContinuarCombo()
			if marcou then
				-- Também notifica servidor que input foi recebido
				EnviarAcao("AtacarLeveEmPe")
				return
			end
		end
	end

	-- Não está em combo - inicia novo ataque
	if estadoInput.agachadoAtivo then
		EnviarAcao("AtacarLeveAgachado")
	else
		EnviarAcao("AtacarLeveEmPe")
	end
end

--- Processa soltar mouse 1
local function ProcessarMouse1Solto()
	if not estadoInput.mouse1Pressionado then
		return
	end

	local tempoSegurando = tick() - estadoInput.tempoMouse1
	estadoInput.mouse1Pressionado = false

	-- Se segurou tempo suficiente, pode ser ataque pesado
	if tempoSegurando >= Configuracao.TempoCarregarPesado then
		EnviarAcao("SoltarPesado")
	end
end

--- Processa segurar mouse 1 (chamado em loop)
local function ProcessarMouse1Segurar()
	if not estadoInput.mouse1Pressionado then
		return
	end

	local tempoSegurando = tick() - estadoInput.tempoMouse1

	-- Após tempo mínimo, inicia carregamento pesado
	if tempoSegurando >= Configuracao.TempoCarregarPesado then
		EnviarAcao("CarregarPesado")
	end
end

--- Processa mouse 2 (bloqueio)
local function ProcessarMouse2Pressionado()
	-- Verifica cooldown de defesa
	local agora = tick()
	if (agora - estadoInput.ultimaDefesa) < Configuracao.CooldownDefesa then
		return -- Ainda em cooldown
	end

	estadoInput.mouse2Pressionado = true
	estadoInput.ultimaDefesa = agora
	EnviarAcao("Bloquear")
end

--- Processa soltar mouse 2
local function ProcessarMouse2Solto()
	if not estadoInput.mouse2Pressionado then
		return
	end

	estadoInput.mouse2Pressionado = false
	EnviarAcao("PararBloqueio")
end

--- Processa agachar
local function ProcessarAgacharPressionado()
	estadoInput.agachadoAtivo = true
	EnviarAcao("Agachar")
end

--- Processa levantar
local function ProcessarAgacharSolto()
	estadoInput.agachadoAtivo = false
	EnviarAcao("Levantar")
end

--- Processa quebrar defesa
local function ProcessarQuebrarDefesa()
	EnviarAcao("QuebrarDefesa")
end

--- Obtém o modo atual do Status
local function ObterModoAtual(): string
	local character = player.Character
	if not character then
		return "Base"
	end

	local status = character:FindFirstChild("Status")
	if not status then
		return "Base"
	end

	local modoAnimacao = status:FindFirstChild("modoAnimacao")
	if modoAnimacao and modoAnimacao:IsA("StringValue") then
		return modoAnimacao.Value
	end

	return "Base"
end

--- Processa quando um Tool é equipado
--- Lê o modoAnimacao do Tool e envia ação de Equipar
--- Se estava desequipando, inverte a animação ao invés de iniciar nova
local function ProcessarToolEquipado(tool: Tool)
	-- Verifica se o Tool tem um modoAnimacao definido
	local modoAnimacaoValue = tool:FindFirstChild("modoAnimacao")
	if not modoAnimacaoValue or not modoAnimacaoValue:IsA("StringValue") then
		warn("[EntradaJogador] Tool '", tool.Name, "' não tem modoAnimacao definido")
		return
	end

	local modoDesejado = modoAnimacaoValue.Value
	if modoDesejado == "" or modoDesejado == "Base" then
		return -- Não equipa se for Base ou vazio
	end

	-- Se estava desequipando o mesmo tool, inverte a animação
	if direcaoEquip == -1 and ultimoToolProcessado == tool then
		direcaoEquip = 1
		toolAtualEquipado = tool

		-- Primeiro inverte localmente, depois notifica servidor
		if _G.InverterEquipAnimacao then
			_G.InverterEquipAnimacao(1)
		end
		EnviarAcao("InverterEquipAnimacao", { direcao = 1, modo = modoDesejado })
		print("[EntradaJogador] Invertendo animação: desequipando -> equipando")
		return
	end

	local modoAtualValue = ObterModoAtual()

	-- Se já está nesse modo e não está em transição, não precisa equipar novamente
	if modoAtualValue == modoDesejado and direcaoEquip == 0 then
		toolAtualEquipado = tool
		return
	end

	-- Equipa o novo modo
	direcaoEquip = 1
	toolAtualEquipado = tool
	ultimoToolProcessado = tool
	EnviarAcao("Equipar", modoDesejado)

	print("[EntradaJogador] Tool equipado: ", tool.Name, " - Modo: ", modoDesejado)
end

--- Processa quando um Tool é desequipado
--- Envia ação de Desequipar para voltar ao modo Base
--- Se estava equipando, inverte a animação ao invés de iniciar nova
local function ProcessarToolDesequipado(tool: Tool)
	-- Verifica se era o tool que estava equipado ou sendo processado
	if toolAtualEquipado ~= tool and ultimoToolProcessado ~= tool then
		return
	end

	-- Se estava equipando o mesmo tool, inverte a animação
	if direcaoEquip == 1 and ultimoToolProcessado == tool then
		direcaoEquip = -1
		toolAtualEquipado = nil

		-- Primeiro inverte localmente, depois notifica servidor
		if _G.InverterEquipAnimacao then
			_G.InverterEquipAnimacao(-1)
		end
		EnviarAcao("InverterEquipAnimacao", { direcao = -1 })
		print("[EntradaJogador] Invertendo animação: equipando -> desequipando")
		return
	end

	local modoAtualValue = ObterModoAtual()

	-- Se já está em Base e não está em transição, não precisa desequipar
	if modoAtualValue == "Base" and direcaoEquip == 0 then
		toolAtualEquipado = nil
		return
	end

	-- Desequipa (volta para Base)
	direcaoEquip = -1
	toolAtualEquipado = nil
	ultimoToolProcessado = tool
	EnviarAcao("Desequipar")

	print("[EntradaJogador] Tool desequipado: ", tool.Name)
end

--- Processa pular
local function ProcessarPular()
	-- Se estiver agachado, levanta primeiro para então pular
	if estadoInput.agachadoAtivo then
		estadoInput.agachadoAtivo = false
		EnviarAcao("Levantar")
		task.delay(0.05, function()
			EnviarAcao("Pular")
		end)
		return
	end

	EnviarAcao("Pular")
end

-- ═══════════════════════════════════════════════════════════════════
-- LISTENERS DE INPUT
-- ═══════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- Mouse
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		ProcessarMouse1Pressionado()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		ProcessarMouse2Pressionado()
		return
	end

	-- Teclado
	if input.KeyCode == Configuracao.TeclaCorrer then
		estadoInput.correndoAtivo = true
		-- Se estiver agachado, levanta antes de iniciar corrida
		if estadoInput.agachadoAtivo then
			estadoInput.agachadoAtivo = false
			EnviarAcao("Levantar")
			task.delay(0.05, function()
				EnviarAcao("Correr")
			end)
		else
			EnviarAcao("Correr")
		end
		return
	end

	if input.KeyCode == Configuracao.TeclaAgachar then
		ProcessarAgacharPressionado()
		return
	end

	if input.KeyCode == Configuracao.TeclaQuebrarDefesa then
		ProcessarQuebrarDefesa()
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		ProcessarPular()
		return
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	-- Mouse
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		ProcessarMouse1Solto()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		ProcessarMouse2Solto()
		return
	end

	-- Teclado
	if input.KeyCode == Configuracao.TeclaCorrer then
		estadoInput.correndoAtivo = false
		-- Evita enviar PararCorrer se ainda estivermos agachados (isso pode resetar animação de agachar)
		if not estadoInput.agachadoAtivo then
			EnviarAcao("PararCorrer")
		end
		return
	end

	if input.KeyCode == Configuracao.TeclaAgachar then
		ProcessarAgacharSolto()
		return
	end
end)

-- ═══════════════════════════════════════════════════════════════════
-- LOOP PARA VERIFICAR SEGURAR MOUSE
-- ═══════════════════════════════════════════════════════════════════

local RunService = game:GetService("RunService")
local ultimaVerificacao = 0

RunService.Heartbeat:Connect(function()
	local agora = tick()

	-- Verifica a cada 0.1 segundos
	if agora - ultimaVerificacao < 0.1 then
		return
	end
	ultimaVerificacao = agora

	ProcessarMouse1Segurar()
end)

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- DETECÇÃO DE TOOLS EQUIPADOS/DESEQUIPADOS
-- ═══════════════════════════════════════════════════════════════════

--- Detecta quando um filho é adicionado ao Character (pode ser Tool)
local function OnChildAdded(child)
	if child:IsA("Tool") then
		ProcessarToolEquipado(child)
	end
end

--- Detecta quando um filho é removido do Character (pode ser Tool desequipado)
local function OnChildRemoved(child)
	if child:IsA("Tool") then
		ProcessarToolDesequipado(child)
	end
end

--- Configura listeners para o Character atual
local function ConfigurarCharacter(char)
	-- Conecta eventos de adicionar/remover filhos
	char.ChildAdded:Connect(OnChildAdded)
	char.ChildRemoved:Connect(OnChildRemoved)

	-- Verifica se já tem algum Tool equipado
	for _, child in pairs(char:GetChildren()) do
		if child:IsA("Tool") then
			ProcessarToolEquipado(child)
			break -- Só pode ter um Tool equipado por vez
		end
	end
end

-- Conecta ao evento de respawn
player.CharacterAdded:Connect(ConfigurarCharacter)

-- Configura o Character inicial (caso o script rode depois do Character carregar)
if player.Character then
	ConfigurarCharacter(player.Character)
end

print("[EntradaJogador] Inicializado - capturando inputs")
