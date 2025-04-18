local Logger = {}

function Logger:Info(msg)
	print("[INFO]:", msg)
end

function Logger:Warn(msg)
	warn("[WARN]:", msg)
end

function Logger:Error(msg)
	error("[ERROR]: " .. msg)
end

return Logger
