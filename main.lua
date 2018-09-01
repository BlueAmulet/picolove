pico8={
	fps=30,
	frames=0,
	pal_transparent={},
	resolution={128, 128},
	palette={
		{0,  0,  0,  255},
		{29, 43, 83, 255},
		{126,37, 83, 255},
		{0,  135,81, 255},
		{171,82, 54, 255},
		{95, 87, 79, 255},
		{194,195,199,255},
		{255,241,232,255},
		{255,0,  77, 255},
		{255,163,0,  255},
		{255,240,36, 255},
		{0,  231,86, 255},
		{41, 173,255,255},
		{131,118,156,255},
		{255,119,168,255},
		{255,204,170,255}
	},
	spriteflags={},
	audio_channels={},
	sfx={},
	music={},
	current_music=nil,
	usermemory={},
	cartdata={},
	clipboard="",
	keypressed={
		[0]={},
		[1]={},
		counter=0
	},
	kbdbuffer={},
	keymap={
		[0]={
			[0]={'left'},
			[1]={'right'},
			[2]={'up'},
			[3]={'down'},
			[4]={'z', 'c', 'n', 'kp-'},
			[5]={'x', 'v', 'm', '8'},
		},
		[1]={
			[0]={'s'},
			[1]={'f'},
			[2]={'e'},
			[3]={'d'},
			[4]={'tab', 'lshift'},
			[5]={'q', 'a'},
		}
	},
	mwheel=0,
	cursor={0, 0},
	camera_x=0,
	camera_y=0,
	draw_palette={},
	display_palette={},
	pal_transparent={},
}

require("strict")
local bit=require("bit")

local flr, abs=math.floor, math.abs

local frametime=1/pico8.fps
local cart=nil
local cartname=nil
local love_args=nil
local scale=nil
local xpadding=nil
local ypadding=nil
local tobase=nil
local topad=nil
local gif_recording=nil
local gif_canvas=nil
local osc
local host_time=0
local retro_mode=false
local paused=false
local mobile=false
local api, cart, gif

local __buffer_count=8
local __buffer_size=1024
local __sample_rate=22050
local channels=1
local bits=16

log=print
--log=function() end

function shdr_unpack(thing)
	return unpack(thing, 0, 15)
end

local function get_bits(v, s, e)
	local mask=bit.lshift(bit.lshift(1, s)-1, e)
	return bit.rshift(bit.band(mask, v))
end

function restore_clip()
	if pico8.clip then
		love.graphics.setScissor(unpack(pico8.clip))
	else
		love.graphics.setScissor()
	end
end

function setColor(c)
	love.graphics.setColor(c/15, 0, 0, 1)
end

local exts={"", ".p8", ".p8.png", ".png"}
function _load(filename)
	filename=filename or cartname
	for i=1, #exts do
		if love.filesystem.getInfo(filename..exts[i]) ~= nil then
			filename=filename..exts[i]
			break
		end
	end
	cartname=filename

	pico8.camera_x=0
	pico8.camera_y=0
	love.graphics.origin()
	pico8.clip=nil
	love.graphics.setScissor()
	api.pal()
	pico8.color=6
	setColor(pico8.color)
	love.graphics.setCanvas(pico8.screen)
	love.graphics.setShader(pico8.draw_shader)

	pico8.cart=cart.load_p8(filename)
	for i=0, 0x1c00-1 do
		pico8.usermemory[i]=0
	end
	for i=1, 64 do
		pico8.cartdata[i]=0
	end
	pico8.cart_id=false
	if pico8.cart._init then pico8.cart._init() end
	if pico8.cart._update60 then
		setfps(60)
	else
		setfps(30)
	end
end

function love.resize(w, h)
	love.graphics.clear()
	-- adjust stuff to fit the screen
	scale=math.max(math.min(w/pico8.resolution[1], h/pico8.resolution[2]), 1)
	if not mobile then
		scale=math.floor(scale)
	end
	xpadding=(w-pico8.resolution[1]*scale)/2
	ypadding=(h-pico8.resolution[2]*scale)/2
	tobase=math.min(w, h)/9
	topad=tobase/8
end

local function note_to_hz(note)
	return 440*2^((note-33)/12)
end

function love.load(argv)
	love_args=argv
	mobile=(love.system.getOS()=="Android" or love.system.getOS()=="iOS")

	love.resize(love.graphics.getDimensions()) -- Setup initial scaling and padding

	osc={}
	-- tri
	osc[0]=function(x)
		local t=x%1
		return (abs(t*2-1)*2-1)*0.5
	end
	-- uneven tri
	osc[1]=function(x)
		local t=x%1
		return (((t<0.875) and (t*16/7) or ((1-t)*16))-1)*0.5
	end
	-- saw
	osc[2]=function(x)
		return (x%1-0.5)*2/3
	end
	-- sqr
	osc[3]=function(x)
		return (x%1<0.5 and 1 or-1)*0.25
	end
	-- pulse
	osc[4]=function(x)
		return (x%1<0.3125 and 1 or-1)*0.25
	end
	-- organ
	osc[5]=function(x)
		x=x*4
		return (abs((x%2)-1)-0.5+(abs(((x*0.5)%2)-1)-0.5)/2-0.1)*0.5
	end
	osc[6]=function()
		local lastx=0
		local sample=0
		local update=false
		local hz48=note_to_hz(48)
		return function(x)
			local hz=((x-lastx)%1)*__sample_rate
			lastx=x
			local scale=hz*(131072/343042875)+(16/889)

			update=not update
			if update then
				sample=sample+scale*(love.math.random()*2-1)
			end
			local output=sample*(45/32)
			if hz > hz48 then
				output=output*(1.1659377442658412e+000-2.3350687035974510e-004*hz+8.3385655344351036e-008*hz^2-1.1509506025078735e-011*hz^3) -- approximate
			end
			sample=math.max(math.min(sample, (6143/31115)), -(6143/31115))
			return output
		end
	end
	-- detuned tri
	osc[7]=function(x)
		x=x*2
		return (abs(((x*127/128)%2)-1)/2+abs((x%2)-1)-1)*2/3
	end
	-- saw from 0 to 1, used for arppregiator
	osc["saw_lfo"]=function(x)
		return x%1
	end

	pico8.audio_source=love.audio.newQueueableSource(__sample_rate, bits, channels, __buffer_count)
	pico8.audio_source:play()
	pico8.audio_buffer=love.sound.newSoundData(__buffer_size, __sample_rate, bits, channels)

	for i=0, 3 do
		pico8.audio_channels[i]={
			oscpos=0,
			sample=0,
			noise=osc[6](),
		}
	end

	love.graphics.clear()
	love.graphics.setDefaultFilter('nearest', 'nearest')
	pico8.screen=love.graphics.newCanvas(pico8.resolution[1], pico8.resolution[2])
	pico8.tmpscr=love.graphics.newCanvas(pico8.resolution[1], pico8.resolution[2])

	local glyphs=""
	for i=32, 127 do
		glyphs=glyphs..string.char(i)
	end
	for i=128, 153 do
		glyphs=glyphs..string.char(194, i)
	end
	local font=love.graphics.newImageFont("font.png", glyphs, 1)
	love.graphics.setFont(font)
	font:setFilter('nearest', 'nearest')

	love.mouse.setVisible(false)
	love.graphics.setLineStyle('rough')
	love.graphics.setPointSize(1)
	love.graphics.setLineWidth(1)

	for i=0, 15 do
		pico8.draw_palette[i]=i
		pico8.pal_transparent[i]=i==0 and 0 or 1
		pico8.display_palette[i]=pico8.palette[i+1]
	end

	local name, version, vendor, device=love.graphics.getRendererInfo()
	local pishaderfix
	if name=="OpenGL ES" and not version:find(" Mesa ", nil, true) and vendor=="Broadcom" then
		print("Using proprietary Broadcom video driver shader fixes")
		pishaderfix=function(code)
			return (code:gsub("ifblock(%b());", function(name)
				name=name:sub(2, -2)
				local kind, length=code:match("extern ([%a_][%w_]-) "..name.."%[(%d-)%]")
				local code=kind.." _"..name..";"
				for i=0, length-1 do
					code=code.."\n\t"..(i==0 and "" or "else ").."if (index=="..i..")\n\t\t_"..name.."="..name.."["..i.."];"
				end
				return code
			end):gsub("([%a_][%w_]-)%[index%]", "_%1"))
		end
	else
		pishaderfix=function(code)
			return (code:gsub("ifblock%b();", ""))
		end
	end

	pico8.draw_shader=love.graphics.newShader(pishaderfix([[
extern float palette[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	int index=int(color.r*15.0+0.5);
	ifblock(palette);
	return vec4(palette[index]/15.0, 0.0, 0.0, 1.0);
}]]))
	pico8.draw_shader:send('palette', shdr_unpack(pico8.draw_palette))

	pico8.sprite_shader=love.graphics.newShader(pishaderfix([[
extern float palette[16];
extern float transparent[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	int index=int(Texel(texture, texture_coords).r*15.0+0.5);
	ifblock(palette);
	ifblock(transparent);
	return vec4(palette[index]/15.0, 0.0, 0.0, transparent[index]);
}]]))
	pico8.sprite_shader:send('palette', shdr_unpack(pico8.draw_palette))
	pico8.sprite_shader:send('transparent', shdr_unpack(pico8.pal_transparent))

	pico8.text_shader=love.graphics.newShader(pishaderfix([[
extern float palette[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	vec4 texcolor=Texel(texture, texture_coords);
	int index=int(color.r*15.0+0.5);
	ifblock(palette);
	return vec4(palette[index]/15.0, 0.0, 0.0, texcolor.a);
}]]))
	pico8.text_shader:send('palette', shdr_unpack(pico8.draw_palette))

	pico8.display_shader=love.graphics.newShader(pishaderfix([[
extern vec4 palette[16];

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	int index=int(Texel(texture, texture_coords).r*15.0+0.5);
	ifblock(palette);
	// lookup the colour in the palette by index
	return palette[index]/255.0;
}]]))
	pico8.display_shader:send('palette', shdr_unpack(pico8.display_palette))

	api=require("api")
	cart=require("cart")
	gif=require("gif")

	-- load the cart
	_load(argv[1] or 'nocart.p8')
end

local function inside(x, y, x0, y0, w, h)
	return (x>=x0 and x<x0+w and y>=y0 and y<y0+h)
end

local function touchcheck(i, x, y)
	local screen_w, screen_h=love.graphics.getDimensions()
	local ytop=screen_h-tobase*4-topad*2
	local length=tobase*3+topad*2

	if i==0 then
		return inside(x, y, topad, ytop, tobase, length)
	elseif i==1 then
		return inside(x, y, tobase*2+topad*3, ytop, tobase, length)
	elseif i==2 then
		return inside(x, y, topad, ytop, length, tobase)
	elseif i==3 then
		return inside(x, y, topad, screen_h-tobase*2, length, tobase)
	elseif i==4 then
		return (screen_w-tobase*8/3-x)^2+(screen_h-tobase*3/2-y)^2<=(tobase/4*3)^2
	elseif i==5 then
		return (screen_w-tobase-x)^2+(screen_h-tobase*2-y)^2<=(tobase/4*3)^2
	end
end

local function update_buttons()
	local init, loop=pico8.fps/2, pico8.fps/7.5
	local touches
	if mobile then
		touches=love.touch.getTouches()
	end
	for p=0, 1 do
		local keymap=pico8.keymap[p]
		local keypressed=pico8.keypressed[p]
		for i=0, 5 do
			local btn=false
			for _, testkey in pairs(keymap[i]) do
				if love.keyboard.isDown(testkey) then
					btn=true
					break
				end
			end
			if not btn and mobile and p==0 then
				for _, id in pairs(touches) do
					btn=touchcheck(i, love.touch.getPosition(id))
					if btn then break end
				end
			end
			if not btn then
				keypressed[i]=false
			elseif not keypressed[i] then
				pico8.keypressed.counter=init
				keypressed[i]=true
			end
		end
	end
	pico8.keypressed.counter=pico8.keypressed.counter-1
	if pico8.keypressed.counter<=0 then
		pico8.keypressed.counter=loop
	end
end

function love.update(dt)
	pico8.frames=pico8.frames+1
	update_buttons()
	if pico8.cart._update60 then
		pico8.cart._update60()
	elseif pico8.cart._update then
		pico8.cart._update()
	end
end

function love.draw()
	-- run the cart's draw function
	if pico8.cart._draw then pico8.cart._draw() end
end

function restore_camera()
	love.graphics.origin()
	love.graphics.translate(-pico8.camera_x, -pico8.camera_y)
end

function flip_screen()
	love.graphics.setShader(pico8.display_shader)
	love.graphics.setCanvas()
	love.graphics.origin()
	love.graphics.setScissor()

	love.graphics.clear()

	local screen_w, screen_h=love.graphics.getDimensions()
	if mobile then
		love.graphics.draw(pico8.screen, xpadding, screen_w>screen_h and ypadding or xpadding, 0, scale, scale)
	else
		love.graphics.draw(pico8.screen, xpadding, ypadding, 0, scale, scale)
	end

	if gif_recording then
		love.graphics.setCanvas(gif_canvas)
		love.graphics.draw(pico8.screen, 0, 0, 0, 2, 2)
		love.graphics.setCanvas()
		gif_recording:frame(gif_canvas:newImageData())
	end

	-- draw touchscreen overlay
	if mobile then
		local col=(love.graphics.getColor())
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.setShader()

		local keys=pico8.keypressed[0]
		love.graphics.rectangle(keys[0] and "fill" or "line", topad, screen_h-tobase*3-topad, tobase, tobase, topad, topad)
		love.graphics.rectangle(keys[3] and "fill" or "line", tobase+topad*2, screen_h-tobase*2, tobase, tobase, topad, topad)
		love.graphics.rectangle(keys[2] and "fill" or "line", tobase+topad*2, screen_h-tobase*4-topad*2, tobase, tobase, topad, topad)
		love.graphics.rectangle(keys[1] and "fill" or "line", tobase*2+topad*3, screen_h-tobase*3-topad, tobase, tobase, topad, topad)
		love.graphics.circle(keys[4] and "fill" or "line", screen_w-tobase*8/3, screen_h-tobase*3/2, tobase/2)
		love.graphics.circle(keys[5] and "fill" or "line", screen_w-tobase, screen_h-tobase*2, tobase/2)
		love.graphics.setColor(col, 0, 0, 1)
	end

	love.graphics.present()

	-- get ready for next time
	love.graphics.setShader(pico8.draw_shader)
	love.graphics.setCanvas(pico8.screen)
	restore_clip()
	restore_camera()
end

local function lowpass(y0, y1, cutoff)
	local RC=1.0/(cutoff*2*3.14)
	local dt=1.0/__sample_rate
	local alpha=dt/(RC+dt)
	return y0+(alpha*(y1-y0))
end

local note_map={[0]='C-', 'C#', 'D-', 'D#', 'E-', 'F-', 'F#', 'G-', 'G#', 'A-', 'A#', 'B-'}

local function note_to_string(note)
	local octave=flr(note/12)
	local note=flr(note%12)
	return string.format("%s%d", note_map[note], octave)
end

local function oldosc(osc)
	local x=0
	return function(freq)
		x=x+freq/__sample_rate
		return osc(x)
	end
end

local function lerp(a, b, t)
	return (b-a)*t+a
end

function update_audio(buffer)
	-- check what sfx should be playing

	for bufferpos=0, __buffer_size-1 do
		if pico8.current_music then
			pico8.current_music.offset=pico8.current_music.offset+7350/(61*pico8.current_music.speed*__sample_rate)
			if pico8.current_music.offset>=32 then
				local next_track=pico8.current_music.music
				if pico8.music[next_track].loop==2 then
					-- go back until we find the loop start
					while true do
						if pico8.music[next_track].loop==1 or next_track==0 then
							break
						end
						next_track=next_track-1
					end
				elseif pico8.music[pico8.current_music.music].loop==4 then
					next_track=nil
				elseif pico8.music[pico8.current_music.music].loop<=1 then
					next_track=next_track+1
				end
				if next_track then
					api.music(next_track)
				end
			end
		end
		local music=pico8.current_music and pico8.music[pico8.current_music.music] or nil

		local sample=0
		for channel=0, 3 do
			local ch=pico8.audio_channels[channel]
			local note, instr, vol, fx
			local freq

			if ch.sfx and pico8.sfx[ch.sfx] then
				local sfx=pico8.sfx[ch.sfx]
				ch.offset=ch.offset+7350/(61*sfx.speed*__sample_rate)
				if sfx.loop_end~=0 and ch.offset>=sfx.loop_end then
					if ch.loop then
						ch.last_step=-1
						ch.offset=sfx.loop_start
					else
						pico8.audio_channels[channel].sfx=nil
					end
				elseif ch.offset>=32 then
					pico8.audio_channels[channel].sfx=nil
				end
			end
			if ch.sfx and pico8.sfx[ch.sfx] then
				local sfx=pico8.sfx[ch.sfx]
				-- when we pass a new step
				if flr(ch.offset)>ch.last_step then
					ch.lastnote=ch.note
					ch.note, ch.instr, ch.vol, ch.fx=unpack(sfx[flr(ch.offset)])
					if ch.instr~=6 then
						ch.osc=osc[ch.instr]
					else
						ch.osc=ch.noise
					end
					if ch.fx==2 then
						ch.lfo=oldosc(osc[0])
					elseif ch.fx>=6 then
						ch.lfo=oldosc(osc["saw_lfo"])
					end
					if ch.vol>0 then
						ch.freq=note_to_hz(ch.note)
					end
					ch.last_step=flr(ch.offset)
				end
				if ch.vol and ch.vol>0 then
					local vol=ch.vol
					if ch.fx==1 then
						-- slide from previous note over the length of a step
						ch.freq=lerp(note_to_hz(ch.lastnote or 0), note_to_hz(ch.note), ch.offset%1)
					elseif ch.fx==2 then
						-- vibrato one semitone?
						ch.freq=lerp(note_to_hz(ch.note), note_to_hz(ch.note+0.5), ch.lfo(8))
					elseif ch.fx==3 then
						-- drop/bomb slide from note to c-0
						local off=ch.offset%1
						-- local freq=lerp(note_to_hz(ch.note), note_to_hz(0), off)
						local freq=lerp(note_to_hz(ch.note), 0, off)
						ch.freq=freq
					elseif ch.fx==4 then
						-- fade in
						vol=lerp(0, ch.vol, ch.offset%1)
					elseif ch.fx==5 then
						-- fade out
						vol=lerp(ch.vol, 0, ch.offset%1)
					elseif ch.fx==6 then
						-- fast appreggio over 4 steps
						local off=bit.band(flr(ch.offset), 0xfc)
						local lfo=flr(ch.lfo(sfx.speed <= 8 and 16 or 8)*4)
						off=off+lfo
						local note=sfx[flr(off)][1]
						ch.freq=note_to_hz(note)
					elseif ch.fx==7 then
						-- slow appreggio over 4 steps
						local off=bit.band(flr(ch.offset), 0xfc)
						local lfo=flr(ch.lfo(sfx.speed <= 8 and 8 or 4)*4)
						off=off+lfo
						local note=sfx[flr(off)][1]
						ch.freq=note_to_hz(note)
					end
					ch.sample=ch.osc(ch.oscpos)*vol/7
					ch.oscpos=ch.oscpos+ch.freq/__sample_rate
				else
					ch.sample=0
				end
			else
				ch.sample=0
			end
			sample=sample+ch.sample
		end
		-- PICO-8 limits max volume to 80%, but since picolove is quieter anyway we opt for increasing the volume
		buffer:setSample(bufferpos, math.min(math.max(sample*1.25, -1), 1))
	end
end

local function isCtrlOrGuiDown()
	return (love.keyboard.isDown('lctrl') or love.keyboard.isDown('lgui') or love.keyboard.isDown('rctrl') or love.keyboard.isDown('rgui'))
end

function love.keypressed(key)
	if cart and pico8.cart._keydown then
		return pico8.cart._keydown(key)
	end
	if key=='r' and isCtrlOrGuiDown() then
		_load()
	elseif key=='q' and isCtrlOrGuiDown() then
		love.event.quit()
	elseif key=='v' and isCtrlOrGuiDown() then
		pico8.clipboard=love.system.getClipboardText()
	elseif key=='pause' then
		paused=not paused
	elseif key=='f1' or key=='f6' then
		-- screenshot
		local filename=cartname..'-'..os.time()..'.png'
		love.graphics.captureScreenshot(filename)
		log('saved screenshot to', filename)
	elseif key=='f3' or key=='f8' then
		-- start recording
		if gif_recording==nil then
			local err
			gif_recording, err=gif.new(cartname..'-'..os.time()..'.gif')
			if not gif_recording then
				log('failed to start recording: '..err)
			else
				gif_canvas=love.graphics.newCanvas(pico8.resolution[1]*2, pico8.resolution[2]*2)
				log('starting record ...')
			end
		else
			log('recording already in progress')
		end
	elseif key=='f4' or key=='f9' then
		-- stop recording and save
		if gif_recording~=nil then
			gif_recording:close()
			log('saved recording to '..gif_recording.filename)
			gif_recording=nil
			gif_canvas=nil
		else
			log('no active recording')
		end
	end
end

function love.keyreleased(key)
	if cart and pico8.cart._keyup then
		return pico8.cart._keyup(key)
	end
end

function love.textinput(text)
	table.insert(pico8.kbdbuffer, text)
	while #pico8.kbdbuffer > 255 do
		table.remove(pico8.kbdbuffer, 1)
	end
	if cart and pico8.cart._textinput then return pico8.cart._textinput(text) end
end

function love.wheelmoved(x, y)
	pico8.mwheel=pico8.mwheel+y
end

function love.graphics.point(x, y)
	love.graphics.rectangle('fill', x, y, 1, 1)
end

function setfps(fps)
	pico8.fps=flr(fps)
	if pico8.fps<=0 then
		pico8.fps=30
	end
	frametime=1/pico8.fps
end

function getMouseX()
	return math.floor((love.mouse.getX()-xpadding)/scale)
end

function getMouseY()
	return math.floor((love.mouse.getY()-ypadding)/scale)
end

function love.run()
	if love.math then
		love.math.setRandomSeed(os.time())
		for i=1, 3 do love.math.random() end
	end
	math.randomseed(os.time())
	for i=1, 3 do math.random() end

	if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

	-- We don't want the first frame's dt to include time taken by love.load.
	if love.timer then love.timer.step() end

	local dt=0

	-- Main loop time.
	return function()
		-- Process events.
		if love.event then
			love.graphics.setCanvas() -- TODO: Rework this
			love.event.pump()
			love.graphics.setCanvas(pico8.screen) -- TODO: Rework this
			for name, a, b, c, d, e, f in love.event.poll() do
				if name == "quit" then
					if not love.quit or not love.quit() then
						return a or 0
					end
				end
				love.handlers[name](a, b, c, d, e, f)
			end
		end

		-- Update dt, as we'll be passing it to update
		if love.timer then dt=dt+love.timer.step() end

		-- Call update and draw
		local render=false
		while dt>frametime do
			host_time=host_time+dt
			if paused then
			else
				if love.update then love.update(frametime) end -- will pass 0 if love.timer is disabled
			end
			dt=dt-frametime
			render=true
		end

		if render and love.graphics and love.graphics.isActive() then
			love.graphics.origin()
			if paused then
				api.rectfill(64-4*4, 60, 64+4*4-2, 64+4+4, 1)
				api.print("paused", 64-3*4, 64, (host_time*20)%8<4 and 7 or 13)
			else
				if love.draw then love.draw() end
			end
			-- draw the contents of pico screen to our screen
			flip_screen()
			-- reset mouse wheel
			pico8.mwheel=0
		end

		for i=1, pico8.audio_source:getFreeBufferCount() do
			update_audio(pico8.audio_buffer)
			pico8.audio_source:queue(pico8.audio_buffer)
			pico8.audio_source:play()
		end

		if love.timer then love.timer.sleep(0.001) end
	end
end
