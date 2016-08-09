local flr=math.floor

-- TODO: Remove this
local scrblitMesh=love.graphics.newMesh(128, "points")
scrblitMesh:setAttributeEnabled("VertexColor", true)

local function __pico8_angle(a)
	-- FIXME: why does this work?
	return (((a-math.pi)/(math.pi*2))+0.25)%1.0
end

local function color(c)
	c=flr(c or 0)%16
	pico8.color=c
	love.graphics.setColor(c, 0, 0, 255)
end

local function warning(msg)
	log(debug.traceback("WARNING: "..msg, 3))
end

local function _horizontal_line(lines, x0, y, x1)
	table.insert(lines, {x0+0.5, y+0.5, x1+1.5, y+0.5})
end

local function _plot4points(lines, cx, cy, x, y)
	_horizontal_line(lines, cx-x, cy+y, cx+x)
	if x~=0 and y~=0 then
		_horizontal_line(lines, cx-x, cy-y, cx+x)
	end
end

--------------------------------------------------------------------------------
-- PICO-8 API

local api={}

function api.flip()
	flip_screen()
	love.timer.sleep(1/pico8.fps)
end

function api.camera(x, y)
	if x~=nil then
		pico8.camera_x=flr(x)
		pico8.camera_y=flr(y)
	else
		pico8.camera_x=0
		pico8.camera_y=0
	end
	restore_camera()
end

function api.clip(x, y, w, h)
	if x and x~="" then
		love.graphics.setScissor(x, y, w, h)
		pico8.clip={x, y, w, h}
	else
		love.graphics.setScissor(0, 0, pico8.resolution[1], pico8.resolution[2])
		pico8.clip=nil
	end
end

function api.cls(c)
	c = tonumber(c) or 0
	if c == nil then
		c = 0
	end

	pico8.clsc = pico8.palette[c+1]
	love.graphics.clear(pico8.clsc)
	pico8.cursor={0, 0}
end

function api.pset(x, y, c)
	if c then
		color(c)
	end
	love.graphics.point(flr(x), flr(y))
end

function api.pget(x, y)
	x=x-pico8.camera_x
	y=y-pico8.camera_y
	if x>=0 and x<pico8.resolution[1] and y>=0 and y<pico8.resolution[2] then
		local r, g, b, a=pico8.screen:newImageData():getPixel(flr(x), flr(y))
		return r
	end
	warning(string.format("pget out of screen %d, %d", x, y))
	return 0
end

function api.color(c)
	color(c)
end

function api.print(str, x, y, col)
	if col then
		color(col)
	end
	if x or y then
		pico8.cursor[1]=flr(tonumber(x) or 0)
		pico8.cursor[2]=flr(tonumber(y) or 0)
	end
	love.graphics.setShader(pico8.text_shader)
	love.graphics.print(tostring(str):gsub("[%z\1-\31\154-\255]", " "):gsub("[\128-\153]", "\194%1"), pico8.cursor[1], pico8.cursor[2])
	love.graphics.setShader(pico8.draw_shader)
	if not x and not y then
		pico8.cursor[1]=0
		pico8.cursor[2]=pico8.cursor[2]+6
	end
end

api.printh=print

function api.cursor(x, y)
	pico8.cursor={x or 0, y or 0}
end

function api.spr(n, x, y, w, h, flip_x, flip_y)
	love.graphics.setShader(pico8.sprite_shader)
	n=flr(n)
	w=w or 1
	h=h or 1
	local q
	if w==1 and h==1 then
		q=pico8.quads[n]
		if not q then
			log('warning: sprite '..n..' is missing')
			return
		end
	else
		local id=string.format("%d-%d-%d", n, w, h)
		if pico8.quads[id] then
			q=pico8.quads[id]
		else
			q=love.graphics.newQuad(flr(n%16)*8, flr(n/16)*8, 8*w, 8*h, 128, 128)
			pico8.quads[id]=q
		end
	end
	if not q then
		log('missing quad', n)
	end
	love.graphics.draw(pico8.spritesheet, q,
		flr(x)+(w*8*(flip_x and 1 or 0)),
		flr(y)+(h*8*(flip_y and 1 or 0)),
		0, flip_x and-1 or 1, flip_y and-1 or 1)
	love.graphics.setShader(pico8.draw_shader)
end

function api.sspr(sx, sy, sw, sh, dx, dy, dw, dh, flip_x, flip_y)
	dw=dw or sw
	dh=dh or sh
	-- FIXME: cache this quad
	local q=love.graphics.newQuad(sx, sy, sw, sh, pico8.spritesheet:getDimensions())
	love.graphics.setShader(pico8.sprite_shader)
	love.graphics.draw(pico8.spritesheet, q,
		flr(dx)+(flip_x and dw or 0),
		flr(dy)+(flip_y and dh or 0),
		0, dw/sw*(flip_x and-1 or 1), dh/sh*(flip_y and-1 or 1))
	love.graphics.setShader(pico8.draw_shader)
end

function api.rect(x0, y0, x1, y1, col)
	if col then
		color(col)
	end
	local w, h=flr(x1-x0), flr(y1-y0)
	if w==0 or h==0 then
		love.graphics.rectangle("fill", flr(x0), flr(y0), w+1, h+1)
	else
		love.graphics.rectangle("line", flr(x0)+0.5, flr(y0)+0.5, w, h)
	end
end

function api.rectfill(x0, y0, x1, y1, col)
	if col then
		color(col)
	end
	if x1<x0 then
		x0, x1=x1, x0
	end
	if y1<y0 then
		y0, y1=y1, y0
	end
	love.graphics.rectangle("fill", flr(x0), flr(y0), flr(x1-x0)+1, flr(y1-y0)+1)
end

function api.circ(ox, oy, r, col)
	if col then
		color(col)
	end
	ox=flr(ox)+0.5
	oy=flr(oy)+0.5
	r=flr(r)
	local points={}
	local x=r
	local y=0
	local decisionOver2=1-x

	while y<=x do
		table.insert(points, {ox+x, oy+y})
		table.insert(points, {ox+y, oy+x})
		table.insert(points, {ox-x, oy+y})
		table.insert(points, {ox-y, oy+x})

		table.insert(points, {ox-x, oy-y})
		table.insert(points, {ox-y, oy-x})
		table.insert(points, {ox+x, oy-y})
		table.insert(points, {ox+y, oy-x})
		y=y+1
		if decisionOver2<0 then
			decisionOver2=decisionOver2+2*y+1
		else
			x=x-1
			decisionOver2=decisionOver2+2*(y-x)+1
		end
	end
	if #points>0 then
		love.graphics.points(points)
	end
end

function api.circfill(cx, cy, r, col)
	if col then
		color(col)
	end
	cx=flr(cx)
	cy=flr(cy)
	r=flr(r)
	local x=r
	local y=0
	local err=1-r

	local lines={}

	while y<=x do
		_plot4points(lines, cx, cy, x, y)
		if err<0 then
			err=err+2*y+3
		else
			if x~=y then
				_plot4points(lines, cx, cy, y, x)
			end
			x=x-1
			err=err+2*(y-x)+3
		end
		y=y+1
	end
	if #lines>0 then
		for i=1, #lines do
			love.graphics.line(lines[i])
		end
	end
end

function api.line(x0, y0, x1, y1, col)
	if col then
		color(col)
	end

	if x0~=x0 or y0~=y0 or x1~=x1 or y1~=y1 then
		warning("line has NaN value")
		return
	end

	x0=flr(x0)
	y0=flr(y0)
	x1=flr(x1)
	y1=flr(y1)

	if x0==x1 or y0==y1 then
		-- simple case draw a straight line
		love.graphics.rectangle("fill", x0, y0, x1-x0+1, y1-y0+1)
	else
		love.graphics.line(x0+0.5, y0+0.5, x1+0.5, y1+0.5)
		-- Final pixel not being reached?
		love.graphics.points(x1+0.5, y1+0.5)
	end
end

function api.pal(c0, c1, p)
	if c0==nil then
		local __palette_modified=false
		local __alpha_modified=false
		for i=0, 15 do
			if pico8.draw_palette[i]~=i then
				pico8.draw_palette[i]=i
				__palette_modified=true
			end
			if pico8.display_palette[i]~=pico8.palette[i+1] then
				pico8.display_palette[i]=pico8.palette[i+1]
				__palette_modified=true
			end
			local alpha=i==0 and 0 or 1
			if pico8.pal_transparent[i]~=alpha then
				pico8.pal_transparent[i]=alpha
				__alpha_modified=true
			end
		end
		if __palette_modified then
			pico8.draw_shader:send('palette', shdr_unpack(pico8.draw_palette))
			pico8.sprite_shader:send('palette', shdr_unpack(pico8.draw_palette))
			pico8.text_shader:send('palette', shdr_unpack(pico8.draw_palette))
			pico8.display_shader:send('palette', shdr_unpack(pico8.display_palette))
		end
		if __alpha_modified then
			pico8.sprite_shader:send('transparent', shdr_unpack(pico8.pal_transparent))
		end
	elseif p==1 and c1~=nil then
		c0=flr(c0)%16
		c1=flr(c1)%16
		if pico8.draw_palette[c0]~=pico8.palette[c1+1] then
			pico8.display_palette[c0]=pico8.palette[c1+1]
			pico8.display_shader:send('palette', shdr_unpack(pico8.display_palette))
		end
	elseif c1~=nil then
		c0=flr(c0)%16
		c1=flr(c1)%16
		if pico8.draw_palette[c0]~=c1 then
			pico8.draw_palette[c0]=c1
			pico8.draw_shader:send('palette', shdr_unpack(pico8.draw_palette))
			pico8.sprite_shader:send('palette', shdr_unpack(pico8.draw_palette))
			pico8.text_shader:send('palette', shdr_unpack(pico8.draw_palette))
		end
	end
end

function api.palt(c, t)
	if c==nil then
		for i=0, 15 do
			pico8.pal_transparent[i]=i==0 and 0 or 1
		end
	else
		c=flr(c)%16
		pico8.pal_transparent[c]=t and 0 or 1
	end
	pico8.sprite_shader:send('transparent', shdr_unpack(pico8.pal_transparent))
end

function api.map(cel_x, cel_y, sx, sy, cel_w, cel_h, bitmask)
	love.graphics.setShader(pico8.sprite_shader)
	cel_x=flr(cel_x)
	cel_y=flr(cel_y)
	sx=flr(sx)
	sy=flr(sy)
	cel_w=flr(cel_w)
	cel_h=flr(cel_h)
	for y=0, cel_h-1 do
		if cel_y+y<64 and cel_y+y>=0 then
			for x=0, cel_w-1 do
				if cel_x+x<128 and cel_x+x>=0 then
					local v=pico8.map[flr(cel_y+y)][flr(cel_x+x)]
					if v~=0 then
						if bitmask==nil or bitmask==0 or bit.band(pico8.spriteflags[v], bitmask)~=0 then
							love.graphics.draw(pico8.spritesheet, pico8.quads[v], sx+8*x, sy+8*y)
						end
					end
				end
			end
		end
	end
	love.graphics.setShader(pico8.draw_shader)
end

function api.mget(x, y)
	x=flr(x or 0)
	y=flr(y or 0)
	if x>=0 and x<128 and y>=0 and y<64 then
		return pico8.map[y][x]
	end
	return 0
end

function api.mset(x, y, v)
	x=flr(x or 0)
	y=flr(y or 0)
	v=flr(v or 0)%256
	if x>=0 and x<128 and y>=0 and y<64 then
		pico8.map[y][x]=v
	end
end

function api.fget(n, f)
	if n==nil then return nil end
	if f~=nil then
		-- return just that bit as a boolean
		if not pico8.spriteflags[flr(n)] then
			warning(string.format('fget(%d, %d)', n, f))
			return false
		end
		return bit.band(pico8.spriteflags[flr(n)], bit.lshift(1, flr(f)))~=0
	end
	return pico8.spriteflags[flr(n)] or 0
end

function api.fset(n, f, v)
	-- fset n [f] v
	-- f is the flag index 0..7
	-- v is boolean
	if v==nil then
		v, f=f, nil
	end
	if f then
		-- set specific bit to v (true or false)
		if v then
			pico8.spriteflags[n]=bit.bor(pico8.spriteflags[n], bit.lshift(1, f))
		else
			pico8.spriteflags[n]=bit.band(pico8.spriteflags[n], bit.bnot(bit.lshift(1, f)))
		end
	else
		-- set bitfield to v (number)
		pico8.spriteflags[n]=v
	end
end

function api.sget(x, y)
	-- return the color from the spritesheet
	x=flr(x)
	y=flr(y)
	if x>=0 and x<128 and y>=0 and y<128 then
		local r, g, b, a=pico8.spritesheet_data:getPixel(x, y)
		return r
	end
	return 0
end

function api.sset(x, y, c)
	x=flr(x)
	y=flr(y)
	c=flr(c or 0)%16
	if x>=0 and x<128 and y>=0 and y<128 then
		pico8.spritesheet_data:setPixel(x, y, c, 0, 0, 255)
		pico8.spritesheet:refresh()
	end
end

function api.music(n, fade_len, channel_mask)
	if n==-1 then
		for i=0, 3 do
			if pico8.music[pico8.current_music.music][i]<64 then
				pico8.audio_channels[i].sfx=nil
				pico8.audio_channels[i].offset=0
				pico8.audio_channels[i].last_step=-1
			end
		end
		pico8.current_music=nil
		return
	end
	local m=pico8.music[n]
	local music_speed=nil
	local music_channel=nil
	for i=0, 3 do
		if m[i]<64 then
			local sfx=pico8.sfx[m[i]]
			if sfx.loop_start>=sfx.loop_end then
				music_speed=sfx.speed
				music_channel=i
				break
			elseif music_speed==nil or music_speed>sfx.speed then
				music_speed=sfx.speed
				music_channel=i
			end
		end
	end
	pico8.audio_channels[music_channel].loop=false
	pico8.current_music={music=n, offset=0, channel_mask=channel_mask or 15, speed=music_speed}
	for i=0, 3 do
		if pico8.music[n][i]<64 then
			pico8.audio_channels[i].sfx=pico8.music[n][i]
			pico8.audio_channels[i].offset=0
			pico8.audio_channels[i].last_step=-1
		end
	end
end

function api.sfx(n, channel, offset)
	-- n=-1 stop sound on channel
	-- n=-2 to stop looping on channel
	channel=channel or-1
	if n==-1 and channel>=0 then
		pico8.audio_channels[channel].sfx=nil
		return
	elseif n==-2 and channel>=0 then
		pico8.audio_channels[channel].loop=false
	end
	offset=offset or 0
	if channel==-1 then
		-- find a free channel
		for i=0, 3 do
			if pico8.audio_channels[i].sfx==nil then
				channel=i
			end
		end
	end
	if channel==-1 then return end
	local ch=pico8.audio_channels[channel]
	ch.sfx=n
	ch.offset=offset
	ch.last_step=offset-1
	ch.loop=true
end

local __scrblit, __scrimg

function api.peek(addr)
	addr=flr(addr)
	if addr<0 then
		return 0
	elseif addr<0x2000 then
		local lo=pico8.spritesheet_data:getPixel(addr*2%128, flr(addr/64))
		local hi=pico8.spritesheet_data:getPixel(addr*2%128+1, flr(addr/64))
		return hi*16+lo
	elseif addr<0x3000 then
		addr=addr-0x2000
		return pico8.map[flr(addr/128)][addr%128]
	elseif addr<0x3100 then
		return pico8.spriteflags[addr-0x3000]
	elseif addr<0x3200 then
		local music=pico8.music[math.floor((addr-0x3100)/4)]
		local channel=addr%4
		return bit.lshift(bit.band(music.loop, bit.lshift(1, channel)), 7-channel) + music[channel]
	elseif addr<0x4300 then
		local sfx=pico8.sfx[math.floor((addr-0x3200)/68)]
		local step=(addr-0x3200)%68
		if step<64 then
			local note=sfx[(step-1)/2]
			if addr%2==0 then
				return bit.lshift(bit.band(note[2], 0x3), 6)+note[1]
			else
				return bit.lshift(note[4], 4)+bit.lshift(note[3], 1)+bit.rshift(bit.band(note[2], 0x4), 2)
			end
		elseif step==65 then
			return sfx.speed
		elseif step==66 then
			return sfx.loop_start
		elseif step==67 then
			return sfx.loop_end
		end
	elseif addr<0x5f00 then
		return pico8.usermemory[addr-0x4300]
	elseif addr<0x5f80 then
		-- FIXME: Draw state
	elseif addr<0x5fc0 then
		-- FIXME: Persistence data
	elseif addr<0x6000 then
		-- FIXME: Unused but memory
	elseif addr<0x8000 then
		addr=addr-0x6000
		local lo=(__scrimg or pico8.screen:newImageData()):getPixel(addr*2%128, flr(addr/64))
		local hi=(__scrimg or pico8.screen:newImageData()):getPixel(addr*2%128+1, flr(addr/64))
		return hi*16+lo
	end
	return 0
end

function api.poke(addr, val)
	addr, val=flr(addr), flr(val)%256
	if addr<0 or addr>=0x8000 then
		error("bad memory access")
	elseif addr<0x1000 then
		local lo=val%16
		local hi=flr(val/16)
		pico8.spritesheet_data:setPixel(addr*2%128, flr(addr/64), lo, 0, 0, 255)
		pico8.spritesheet_data:setPixel(addr*2%128+1, flr(addr/64), hi, 0, 0, 255)
	elseif addr<0x2000 then
		local lo=val%16
		local hi=flr(val/16)
		pico8.spritesheet_data:setPixel(addr*2%128, flr(addr/64), lo, 0, 0, 255)
		pico8.spritesheet_data:setPixel(addr*2%128+1, flr(addr/64), hi, 0, 0, 255)
		pico8.map[flr(addr/128)][addr%128]=val
	elseif addr<0x3000 then
		addr=addr-0x2000
		pico8.map[flr(addr/128)][addr%128]=val
	elseif addr<0x3100 then
		pico8.spriteflags[addr-0x3000]=val
	elseif addr<0x3200 then
		local music=pico8.music[math.floor((addr-0x3100)/4)]
		music[addr%4]=bit.band(val, 0x7F)
		local loop=bit.lshift(1, addr%4)
		if bit.band(val, 0x80)~=0 then
			music.loop=bit.bor(music.loop, loop)
		else
			music.loop=bit.band(music.loop, bit.bnot(loop))
		end
	elseif addr<0x4300 then
		local sfx=pico8.sfx[math.floor((addr-0x3200)/68)]
		local step=(addr-0x3200)%68
		if step<64 then
			local note=sfx[math.floor(step/2)]
			if addr%2==0 then
				note[1]=bit.band(val, 0x3f)
				note[2]=bit.rshift(bit.band(val, 0xc0), 6)+bit.band(note[2], 0x4)
			else
				note[2]=bit.lshift(bit.band(val, 0x1), 2)+bit.band(note[2], 0x3)
				note[3]=bit.rshift(bit.band(note, 0xe), 1)
				note[4]=bit.rshift(bit.band(note, 0x70), 4)
			end
		elseif step==65 then
			sfx.speed=val
		elseif step==66 then
			sfx.loop_start=val
		elseif step==67 then
			sfx.loop_end=val
		end
	elseif addr<0x5f00 then
		pico8.usermemory[addr-0x4300]=val
	elseif addr<0x5f80 then
		-- FIXME: Draw state
	elseif addr<0x5fc0 then
		-- FIXME: Persistence data
	elseif addr<0x6000 then
		-- FIXME: Unused but memory
	elseif addr<0x8000 then
		addr=addr-0x6000
		local lo=val%16
		local hi=flr(val/16)
		if __scrblit then
			table.insert(__scrblit, {addr*2%128, flr(addr/64), 0, 0, lo, 0, 0, 255})
			table.insert(__scrblit, {addr*2%128+1, flr(addr/64), 0, 0, hi, 0, 0, 255})
		else
			love.graphics.setColor(lo, 0, 0, 255)
			love.graphics.point(addr*2%128, flr(addr/64))
			love.graphics.setColor(hi, 0, 0, 255)
			love.graphics.point(addr*2%128+1, flr(addr/64))
			love.graphics.setColor(pico8.color, 0, 0, 255)
		end
	end
end

function api.memcpy(dest_addr, source_addr, len)
	if len<1 or dest_addr==source_addr then
		return
	end

	-- Screen Hack
	if source_addr+len-1>=0x6000 then
		__scrimg=pico8.screen:newImageData()
	end
	if dest_addr+len-1>=0x6000 then
		__scrblit={}
		if scrblitMesh:getVertexCount()<len*2 then
			scrblitMesh=love.graphics.newMesh(len*2, "points")
			scrblitMesh:setAttributeEnabled("VertexColor", true)
		end
	end

	local offset=dest_addr-source_addr
	if source_addr>dest_addr then
		for i=dest_addr, dest_addr+len-1 do
			api.poke(i, api.peek(i-offset))
		end
	else
		for i=dest_addr+len-1, dest_addr, -1 do
			api.poke(i, api.peek(i-offset))
		end
	end
	if __scrblit then
		scrblitMesh:setVertices(__scrblit)
		scrblitMesh:setDrawRange(1, #__scrblit)
		love.graphics.setColor(255, 255, 255, 255)
		love.graphics.draw(scrblitMesh)
		love.graphics.setColor(pico8.color, 0, 0, 255)
	end
	__scrblit, __scrimg=nil
end

function api.memset(dest_addr, val, len)
	if len<1 then
		return
	end
	for i=dest_addr, dest_addr+len-1 do
		api.poke(i, val)
	end
end

function api.reload(dest_addr, source_addr, len)
end

function api.cstore(dest_addr, source_addr, len)
end

function api.rnd(x)
	return math.random()*(x or 1)
end

function api.srand(seed)
	return math.random(flr(seed*0x10000))
end

api.flr=math.floor

function api.sgn(x)
	return x<0 and-1 or 1
end

api.abs=math.abs

function api.min(a, b)
	if a==nil or b==nil then
		warning('min a or b are nil returning 0')
		return 0
	end
	if a<b then return a end
	return b
end

function api.max(a, b)
	if a==nil or b==nil then
		warning('max a or b are nil returning 0')
		return 0
	end
	if a>b then return a end
	return b
end

function api.mid(x, y, z)
	return (x<=y)and((y<=z)and y or((x<z)and z or x))or((x<=z)and x or((y<z)and z or y))
end

function api.cos(x)
	return math.cos((x or 0)*math.pi*2)
end

function api.sin(x)
	return-math.sin((x or 0)*math.pi*2)
end

api.sqrt=math.sqrt

function api.atan2(y, x)
	return __pico8_angle(math.atan2(y, x))
end

function api.band(x, y)
	return bit.band(x*0x10000, y*0x10000)/0x10000
end

function api.bor(x, y)
	return bit.bor(x*0x10000, y*0x10000)/0x10000
end

function api.bxor(x, y)
	return bit.bxor(x*0x10000, y*0x10000)/0x10000
end

function api.bnot(x)
	return bit.bnot(x*0x10000)/0x10000
end

function api.shl(x, y)
	return bit.lshift(x*0x10000, y)/0x10000
end

function api.shr(x, y)
	return bit.arshift(x*0x10000, y)/0x10000
end

function api.run()
	love.graphics.setCanvas(pico8.screen)
	love.graphics.setShader(pico8.draw_shader)
	restore_clip()
	love.graphics.origin()
	for i=0, 0x1c00-1 do
		pico8.usermemory[i]=0
	end
	for i=0, 63 do
		pico8.cartdata[i]=0
	end
	if pico8.cart._init then pico8.cart._init() end
end

function api.btn(i, p)
	if i~=nil or p~=nil then
		p=p or 0
		if p<0 or p>1 then
			return false
		end
		return not not pico8.keypressed[p][i]
	else
		local bits=0
		for i=0, 5 do
			bits=bits+(pico8.keypressed[0][i] and 2^i or 0)
			bits=bits+(pico8.keypressed[1][i] and 2^(i+8) or 0)
		end
		return bits
	end
end

function api.btnp(i, p)
	if i~=nil or p~=nil then
		p=p or 0
		if p<0 or p>1 then
			return false
		end
		local v=pico8.keypressed.counter
		if pico8.keypressed[p][i] and (v==0 or (v>=12 and v%4==0)) then
			return true
		end
		return false
	else
		local v=pico8.keypressed.counter
		v=(v==0 or (v>=12 and v%4==0))
		local bits=0
		for i=0, 5 do
			bits=bits+((pico8.keypressed[0][i] and v) and 2^i or 0)
			bits=bits+((pico8.keypressed[i][i] and v) and 2^(i+8) or 0)
		end
		return bits
	end
end

function api.cartdata(id)
end

function api.dget(index)
	index=flr(index)
	if index<0 or index>63 then
		warning('cartdata index out of range')
		return
	end
	return pico8.cartdata[index]
end

function api.dset(index, value)
	index=flr(index)
	if index<0 or index>63 then
		warning('cartdata index out of range')
		return
	end
	pico8.cartdata[index]=value
end

function api.stat(x)
	return 0
end

api.sub=string.sub
api.pairs=pairs
api.type=type
api.assert=assert
api.setmetatable=setmetatable
api.cocreate=coroutine.create
api.coresume=coroutine.resume
api.yield=coroutine.yield
api.costatus=coroutine.status

-- The functions below are normally attached to the program code, but are here for simplicity
function api.all(a)
	if a==nil or #a==0 then
		return function() end
	end
	local i, li=1
	return function()
		if (a[i]==li) then i=i+1 end
		while(a[i]==nil and i<=#a) do i=i+1 end
		li=a[i]
		return a[i]
	end
end

function api.foreach(a, f)
	for v in api.all(a) do
		f(v)
	end
end

function api.count(a)
	local count=0
	for i=1, #a do
		if a[i]~=nil then count=count+1 end
	end
	return count
end

function api.add(a, v)
	if a==nil then return end
	a[#a+1]=v
end

function api.del(a, dv)
	if a==nil then return end
	for i=1, #a do
		if a[i]==dv then
			table.remove(a, i)
			return
		end
	end
end

return api
