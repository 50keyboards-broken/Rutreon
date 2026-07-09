
function Get_input()
    io.write("\n-Name> ")
    return io.read()
end
VXBOOTname = Get_input()
ASSEMin = {}
PKTHeaderout = {
    "0000",
    "0000",
    "0000",
}
PKTOperandout = {
    "000000000000",
    "000000000000",
    "000000000000",
}
VXBOOTHeaderout = {
    "000000",
    "000000",
}
VXBOOTOperandout = {
    "000000000000",
    "000000000000",
}
VRTXCurrentout = {}
VXBOOTout = {}
local Readerpointer = 1
local PKTcycle = 1
local PKTcount = 1
local BOOTcycle = 1
local ExplicitInstruction = false
Skipcycle = false
GELOCinvert = {
    G = false,
    E = false,
    L = false,
    O = false,
    C = false,
    invert = false,
}
GELOCorder = {
    "G",
    "E",
    "L",
    "O",
    "C",
    "invert"
}

for line in io.lines("IN.VX-ASSEM") do
    if line ~= "" then
        table.insert(ASSEMin, line)
    end
end

--quick helper functions
function RTword(OPERAND)
    local rpos    = OPERAND:find("r")
    local tpos    = OPERAND:find("t")
    local channel = OPERAND:sub(1, rpos - 1)
    local middle  = OPERAND:sub(rpos + 1, tpos - 1)
    local addr    = OPERAND:sub(tpos + 1)
    function Region(bits, size)
        if bits == "" then
            return string.rep("0", size)
        elseif bits == "*" then
            return string.rep("1", size)
        else
            return string.rep("0", size - #bits) .. bits
        end
    end

    channel = Region(channel, 2)
    middle  = Region(middle, 6)
    addr    = Region(addr, 4)

    OPERAND = channel .. middle .. addr
    return OPERAND
end

function ToBinary(num, bits)
    if not num then
        print("Expected number paired with: "..ASSEMin[Readerpointer])
        os.exit()
    end
    local result = ""
    for i = bits - 1, 0, -1 do
        local bit = math.floor(num / (2 ^ i)) % 2
        result = result .. bit
    end
    return result
end

function Getoperand(OPERAND)
    local Channel, Value = OPERAND:match("^(%S+)%s*(.*)$")
    REGION = CHANNELLUT[Channel]
    if (REGION) then
        return REGION(ToBinary(tonumber(Value),10))
    end
    local tryRTword = string.sub(OPERAND, 1,1)
    if tryRTword == "#" then
        RTwordString = string.sub(OPERAND, 2,32)
        return RTword(RTwordString)
    else
        NumberDecimalString = string.sub(OPERAND, 1,3)
        return ToBinary(tonumber(NumberDecimalString), 12)
    end
end

function SplitOperands(str)
    local operands = {}

    for word in str:gmatch("%S+") do
        table.insert(operands, word)
    end

    return operands
end

function ParseJUMP(OPERANDS)
    local Operand6b = ""
    for _, Obj in ipairs(OPERANDS) do
        local func = JUMPFLAGS_LUT[Obj]
        if func then
            func()
        end
    end
    for _, key in ipairs(GELOCorder) do
        if GELOCinvert[key] then
            Operand6b = Operand6b .. "1"
        else
            Operand6b = Operand6b .. "0"
        end
    end
    GELOCinvert.G = false
    GELOCinvert.E = false
    GELOCinvert.L = false
    GELOCinvert.O = false
    GELOCinvert.C = false
    GELOCinvert.invert = false
    return Operand6b
end

-- later me shud put these mini ops into LUTs but for now its for readability.
function TryforExplicitInstruction(CurrentLine)
    local opcode, rest = CurrentLine:match("^(%S+)%s*(.*)$")
    local OPERANDS = SplitOperands(rest)
    if opcode == "VMEC" then
        ExplicitInstruction = true
        PKTHeaderout[PKTcycle] = RUTREON_ASSEM_LUT["VMEC"]
        if OPERANDS[1] == "SELECT" then
            PKTOperandout[PKTcycle] = "00000000"..ToBinary(tonumber(OPERANDS[2]), 4)
        elseif OPERANDS[1] == "IMPORT" then
            PKTOperandout[PKTcycle] = "0100"..ToBinary(tonumber(OPERANDS[2]), 4)..ToBinary(tonumber(OPERANDS[3]), 4)
        end
    elseif opcode == "XPRT" then
        ExplicitInstruction = true
        PKTHeaderout[PKTcycle] = RUTREON_ASSEM_LUT["XPRT"]
        if OPERANDS[1] == "SEND" then
            if OPERANDS[2] == "THREADSHARE" then
                PKTOperandout[PKTcycle] = "0000"..ToBinary(tonumber(OPERANDS[3]),4)..ToBinary(tonumber(OPERANDS[4]),4)
            elseif OPERANDS[2] == "VRAM" then
                PKTOperandout[PKTcycle] = "000100000000"
            elseif OPERANDS[2] == "PORT" then
                PKTOperandout[PKTcycle] = "001000000000"
            else
                print("INVALID XPRT BUS :"..OPERANDS[2])
                os.exit()
            end
        elseif OPERANDS[1] == "READ" then
            PKTOperandout[PKTcycle] = "01000000"..ToBinary(tonumber(OPERANDS[2]),4)
        elseif OPERANDS[1] == "WAIT" then
            PKTOperandout[PKTcycle] = "100000000000"
        elseif OPERANDS[1] == "IMPORT" then
            PKTOperandout[PKTcycle] = "11000000"..ToBinary(tonumber(OPERANDS[2]),4)
        end
    elseif opcode == "ARTH" or opcode == "CART" then
        ExplicitInstruction = true
        local GetMATH = MATHLUT[OPERANDS[1]]
        if not GetMATH then
            print("INVALID MATH MODE: "..OPERANDS[1])
            os.exit()
        end
        if opcode == "ARTH" then
            PKTHeaderout[PKTcycle] = RUTREON_ASSEM_LUT["ARTH"]
            PKTOperandout[PKTcycle] = GetMATH..ToBinary(tonumber(OPERANDS[2]),10)
        else
            PKTHeaderout[PKTcycle] = RUTREON_ASSEM_LUT["CART"]
            PKTOperandout[PKTcycle] = GetMATH.."000000"..ToBinary(tonumber(OPERANDS[2]),4)
        end
    elseif opcode == "LGIC" or opcode == "CLGC" then
        ExplicitInstruction = true
        local GetLOGIC = LOGICLUT[OPERANDS[1]]
        if not GetLOGIC then
            print("INVALID LOGIC MODE: "..OPERANDS[1])
            os.exit()
        end
        if opcode == "LGIC" then
            PKTHeaderout[PKTcycle] = RUTREON_ASSEM_LUT["LGIC"]
            PKTOperandout[PKTcycle] = GetLOGIC..ToBinary(tonumber(OPERANDS[2]),10)
        else
            PKTHeaderout[PKTcycle] = RUTREON_ASSEM_LUT["CLGC"]
            PKTOperandout[PKTcycle] = GetLOGIC.."000000"..ToBinary(tonumber(OPERANDS[2]),4)
        end
    elseif opcode == "FLAG" or opcode == "CFLG" then
        ExplicitInstruction = true
        GetFLAG = FLAGLUT[OPERANDS[1]]
        if not GetFLAG then
            print("INVALID FLAG MODE: "..OPERANDS[1])
            os.exit()
        end
        if opcode == "FLAG" then
            PKTHeaderout[PKTcycle] = RUTREON_ASSEM_LUT["FLAG"]
            PKTOperandout[PKTcycle] = GetFLAG .. ToBinary(tonumber(OPERANDS[2]), 10)
        else
            PKTHeaderout[PKTcycle] = RUTREON_ASSEM_LUT["CFLG"]
            PKTOperandout[PKTcycle] = GetFLAG .. "000000" .. ToBinary(tonumber(OPERANDS[2]), 4)
        end
    elseif opcode == "JUMP" then
        ExplicitInstruction = true
        PKTHeaderout[PKTcycle] = RUTREON_ASSEM_LUT["JUMP"]
        if OPERANDS[1] == "LOCAL" then
            PKTOperandout[PKTcycle] = "00"..ParseJUMP(OPERANDS)..ToBinary(tonumber(OPERANDS[#OPERANDS]),4)
        elseif OPERANDS[1] == "LIVE" then
            PKTOperandout[PKTcycle] = "010"..ToBinary(tonumber(OPERANDS[2]),5)..ToBinary(tonumber(OPERANDS[3]),4)
        elseif OPERANDS[1] == "ACCEPT" then
            PKTOperandout[PKTcycle] = "10000000"..ToBinary(tonumber(OPERANDS[2]),4)
        elseif  OPERANDS[1] == "REQUEST" then
            PKTOperandout[PKTcycle] = "110"..ToBinary(tonumber(OPERANDS[2]),5).."0000"
        else
            print("INVALID JUMP MODE: "..OPERANDS[1])
            os.exit()
        end
    elseif opcode == "SLEP" then
        ExplicitInstruction = true
        PKTHeaderout[PKTcycle] = RUTREON_ASSEM_LUT["SLEP"]
        if OPERANDS[1] == "SETFLAG" then
            if tonumber(OPERANDS[2]) > 1 then
                print("INVALID VALUE TO SET FLAG")
                os.exit()
            end
            PKTOperandout[PKTcycle] = "11"..OPERANDS[2].."00000"..ToBinary(tonumber(OPERANDS[3]),4)
        else
            local GetSLEEP = SLEEPFLAGS_LUT[OPERANDS[1]]
            if not GetSLEEP then
                print("INVALID SLEEP MODE")
                os.exit()
            end
            PKTOperandout[PKTcycle] = GetSLEEP..ToBinary(tonumber(OPERANDS[2]),10)
        end
    else
        ExplicitInstruction = false
    end
end

--LUTs
RUTREON_ASSEM_LUT = {
    NOP  = "0000",
    WRTE = "0001",
    READ = "0010",
    MECO = "0011",
    VMEC = "0100",
    XPRT = "0101",
    ARTH = "0110",
    CART = "0111",
    LGIC = "1000",
    CLGC = "1001",
    FLAG = "1010",
    CFLG = "1011",
    JUMP = "1100",
    SLEP = "1101",
    STOP = "STOP"
}
ThreadUnitLUT = {
    TU0 = "0000",
    TU1 = "0001",
    TU2 = "0010",
    TU3 = "0011",
    TU4 = "0100",
    TU5 = "0101",
}
CHANNELLUT = {
    STORAGE = function(OPERAND) return "00"..string.sub(OPERAND, 3,10) end,
    VRAM = function(OPERAND) return "01"..string.sub(OPERAND, 3,10) end,
    RMEM0 = function(OPERAND) return "10"..string.sub(OPERAND, 3,10) end,
    RMEM1 = function(OPERAND) return "11"..string.sub(OPERAND, 3,10) end,
    VRTX = function(OPERAND) return "11111110"..string.sub(OPERAND, 7,10) end,
    MECO_LOOPBACK = function() return "111111101111" end,
    CACHE = function(OPERAND) return "11111111"..string.sub(OPERAND, 7,10) end,
}
MATHLUT = {
    ["+"] = "00",
    ["-"] = "01",
    ["<<"] = "10",
    [">>"] = "11",
}
LOGICLUT = {
    AND = "00",
    OR = "01",
    XOR = "10",
    NOT = "11"
}
FLAGLUT = {
    ["="] = "00",
    [">"] = "01",
    ["<"] = "10",
}
JUMPFLAGS_LUT = {
    ["<"] = function() GELOCinvert["G"] = true end,
    ["="] = function() GELOCinvert["E"] = true end,
    [">"] = function() GELOCinvert["L"] = true end,
    ["Z"] = function() GELOCinvert["O"] = true end,
    ["C"] = function() GELOCinvert["C"] = true end,
    ["!"] = function() GELOCinvert["invert"] = true end,
}
SLEEPFLAGS_LUT = {
    CYCLE = "00",
    PORT = "01",
    FLAG = "10",
}

function DecodeLoop()
    Skipcycle = true
    CurrentLine = ASSEMin[Readerpointer]
    CheckAssemCommand = string.sub(CurrentLine, 1, 1)
    if CheckAssemCommand == "$" then
        local Command = SplitOperands(CurrentLine)
        if Command[1] == "$VXID" then
            RAWOPERAND = Command[2]
            BINOPERAND = Getoperand(RAWOPERAND)
            OPERAND = tonumber(BINOPERAND, 2)
            VX48Writer(OPERAND)
            return
        elseif Command[1] == "$BOOT" then
            RAWTU = Command[2]
            BINTU = ThreadUnitLUT[RAWTU]
            RAWOPERAND = Command[3]
            BINOPERAND = Getoperand(RAWOPERAND)
            BIN5OPERAND = string.sub(BINOPERAND, 8, 12)
            OPERAND = tonumber(BINOPERAND, 2)
            if OPERAND >= 32 then
                print("TUID OUT OF BOUNDS")
                os.exit()
            end
            VXBOOTHeaderout[BOOTcycle] = "010000"
            LINE = BINTU.."000"..BIN5OPERAND
            VXBOOTOperandout[BOOTcycle] = LINE
            BOOTcycle = BOOTcycle + 1
            return
        elseif Command[1] == "$PACEEXIT" then
            BOOTcycle = BOOTcycle + 1
            return
        elseif Command[1] == "CONF" then
            print("i dont have ideas for this yet.")
            return
        else
            if Command[1] == "$ASSEMBLEDONE" then
                VXBOOTWriter()
                print("-: ASSEMBLE COMPLETE :-")
                os.exit()
            end
        end
    else
        Skipcycle = false
        TryforExplicitInstruction(CurrentLine)
        if ExplicitInstruction == true then
            return
        end
        RAWINSTRUCTION = string.sub(CurrentLine, 1, 4)
        BININSTRUCTION = RUTREON_ASSEM_LUT[RAWINSTRUCTION]
        if not BININSTRUCTION then
            print("Expected Valid Instruction found: ("..CurrentLine..") <- INVALID")
            os.exit()
        end
        RAWOPERAND = string.sub(CurrentLine, 6,32)
        BINOPERAND = Getoperand(RAWOPERAND)
        PKTHeaderout[PKTcycle] = BININSTRUCTION
        PKTOperandout[PKTcycle] = BINOPERAND
    end
end

function VXBOOTGatherer()
    BOOTcycle = 1
    Header = VXBOOTHeaderout[1]..VXBOOTHeaderout[2]
    table.insert(VXBOOTout, Header)
    table.insert(VXBOOTout, VXBOOTOperandout[1])
    table.insert(VXBOOTout, VXBOOTOperandout[2])
    VXBOOTHeaderout[1] = "000000"
    VXBOOTHeaderout[2] = "000000"
    VXBOOTOperandout[1] = "000000000000"
    VXBOOTOperandout[2] = "000000000000"
end

function VRTXGatherer()
    PKTcount = PKTcount + 1
    HeaderTRYTE = PKTHeaderout[1]..PKTHeaderout[2]..PKTHeaderout[3]
    table.insert(VRTXCurrentout, HeaderTRYTE)
    table.insert(VRTXCurrentout, PKTOperandout[1])
    table.insert(VRTXCurrentout, PKTOperandout[2])
    table.insert(VRTXCurrentout, PKTOperandout[3])
    PKTHeaderout[1] = "0000"
    PKTHeaderout[2] = "0000"
    PKTHeaderout[3] = "0000"
    PKTOperandout[1] = "000000000000"
    PKTOperandout[2] = "000000000000"
    PKTOperandout[3] = "000000000000"
end

function VX48Writer(VXID)
    ASSEMout = io.open(VXID..".VX48", "w")
    while true do
        if  PKTcount <= 4 then
            VRTXGatherer()
        else
            break
        end
    end
    for _, data in ipairs(VRTXCurrentout) do
        ASSEMout:write(data.."\n")
    end
    ASSEMout:close()
    print(VXID..".VX48 Assemble Success ✓")
    VRTXCurrentout = {}
    PKTcycle = 1
    PKTcount = 1
end
function VXBOOTWriter()
    BOOTout = io.open(VXBOOTname..".VXBOOT", "w")
    if BOOTcycle ~= 1 then
        VXBOOTGatherer()
    end
    for _, data in ipairs(VXBOOTout) do
        BOOTout:write(data.."\n")
    end
    BOOTout:close()
    print(VXBOOTname..".VXBOOT Write Success ✓")
end

while true do
	if PKTcycle > 3 then
        if PKTcount > 4 then
            print("No space! Only 12 Insructions per VRTX.")
            os.exit()
        end
        VRTXGatherer()
        PKTcycle = 1
    end
    DecodeLoop()
    Readerpointer = Readerpointer + 1
    if not Skipcycle then
        PKTcycle = PKTcycle + 1
    end
    if BOOTcycle >= 3 then
        VXBOOTGatherer()
    end
end
