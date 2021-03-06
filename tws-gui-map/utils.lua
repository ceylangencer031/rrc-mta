loadstring(exports["tws-shared"]:include("utils"))()
loadstring(exports["tws-shared"]:include("mouse_utils"))()
loadstring(exports["tws-shared"]:include("dxGUI"))()

screenWidth, screenHeight = guiGetScreenSize()
mainScale = 1 * screenHeight / 600

function dxDrawScreenShadow()
    dxDrawImage(0, 0, screenWidth, screenHeight, "images/screen_shadow.png")
    dxDrawImage(0, 0, screenWidth, screenHeight, "images/screen_shadow.png", 180, 0, 0)
end

local cornerTexture = dxCreateTexture("images/corner.png", "argb", true, "clamp")

function dxDrawRoundRectangle(x, y, w, h, color, radius)
    dxDrawImage(x, y, radius, radius, cornerTexture, 0, 0, 0, color)
    dxDrawRectangle(x, y + radius, radius, h - radius * 2, color)
    dxDrawImage(x, y + h - radius, radius, radius, cornerTexture, 270, 0, 0, color)
    dxDrawRectangle(x + radius, y, w - radius * 2, h, color)
    dxDrawImage(x + w - radius, y, radius, radius, cornerTexture, 90, 0, 0, color)
    dxDrawRectangle(x + w - radius, y + radius, radius, h - radius * 2, color)
    dxDrawImage(x + w - radius, y + h - radius, radius, radius, cornerTexture, 180, 0, 0, color)
end