local PLAYER = FindMetaTable("Player")

function PLAYER:SendTranslatedText(message)
    net.Start("autils_sendtranslatedtext")
        net.WriteString(message)
    net.Send(self)
end

function PLAYER:SendColoredTable(...)
    net.Start("autils_sendcolortable")
        net.WriteTable({...})
    net.Send(self)
end