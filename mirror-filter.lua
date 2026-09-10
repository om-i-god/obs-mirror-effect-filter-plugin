-- mirror-filter.lua
-- A mirror / kaleidoscope video filter for OBS.
-- Tools -> Scripts -> "+" -> pick this file.
-- Then: right-click any source -> Filters -> "+" -> Mirror

obs = obslua

local SHADER = [[
uniform float4x4 ViewProj;
uniform texture2d image;

uniform int   mode;
uniform float pivot_x;
uniform float pivot_y;
uniform float angle;        // degrees
uniform float aspect;       // width / height
uniform int   segments;     // kaleidoscope only
uniform float clip_outside; // >0.5 = transparent outside the source frame

sampler_state textureSampler {
	Filter    = Linear;
	AddressU  = Clamp;
	AddressV  = Clamp;
};

struct VertData {
	float4 pos : POSITION;
	float2 uv  : TEXCOORD0;
};

VertData VSDefault(VertData v_in)
{
	VertData vert_out;
	vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
	vert_out.uv  = v_in.uv;
	return vert_out;
}

float4 PSMirror(VertData v_in) : TARGET
{
	float2 pivot = float2(pivot_x, pivot_y);
	float2 asp   = float2(aspect, 1.0);

	// into aspect-corrected space centred on the mirror line
	float2 p = (v_in.uv - pivot) * asp;

	// rotate so the mirror line lies on the vertical axis
	float t = -angle * 0.017453292;
	float s = sin(t);
	float c = cos(t);
	p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

	if (mode == 5) {
		// radial fold
		float r   = length(p);
		float a   = atan2(p.y, p.x);
		float seg = 6.283185307 / (float)segments;
		a = a - seg * floor(a / seg);   // [0, seg)
		a = abs(a - seg * 0.5);         // [0, seg/2]
		p = float2(cos(a), sin(a)) * r;
	} else {
		if (mode == 0 && p.x > 0.0) p.x = -p.x;   // left  -> right
		if (mode == 1 && p.x < 0.0) p.x = -p.x;   // right -> left
		if (mode == 2 && p.y > 0.0) p.y = -p.y;   // top   -> bottom
		if (mode == 3 && p.y < 0.0) p.y = -p.y;   // bottom-> top
		if (mode == 4) {                          // quad
			if (p.x > 0.0) p.x = -p.x;
			if (p.y > 0.0) p.y = -p.y;
		}
		// rotate back so the image stays upright
		p = float2(p.x * c + p.y * s, -p.x * s + p.y * c);
	}

	float2 uv = p / asp + pivot;

	if (clip_outside > 0.5 &&
	    (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0))
		return float4(0.0, 0.0, 0.0, 0.0);

	return image.Sample(textureSampler, uv);
}

technique Draw
{
	pass
	{
		vertex_shader = VSDefault(v_in);
		pixel_shader  = PSMirror(v_in);
	}
}
]]

local info = {}
info.id           = "jazzi_mirror_filter"
info.type         = obs.OBS_SOURCE_TYPE_FILTER
info.output_flags = obs.OBS_SOURCE_VIDEO

info.get_name = function()
	return "Mirror"
end

info.create = function(settings, source)
	local data = {}
	data.source = source
	data.width  = 1
	data.height = 1

	obs.obs_enter_graphics()
	data.effect = obs.gs_effect_create(SHADER, "mirror_filter", nil)
	if data.effect ~= nil then
		data.p_mode    = obs.gs_effect_get_param_by_name(data.effect, "mode")
		data.p_pivot_x = obs.gs_effect_get_param_by_name(data.effect, "pivot_x")
		data.p_pivot_y = obs.gs_effect_get_param_by_name(data.effect, "pivot_y")
		data.p_angle   = obs.gs_effect_get_param_by_name(data.effect, "angle")
		data.p_aspect  = obs.gs_effect_get_param_by_name(data.effect, "aspect")
		data.p_seg     = obs.gs_effect_get_param_by_name(data.effect, "segments")
		data.p_clip    = obs.gs_effect_get_param_by_name(data.effect, "clip_outside")
	end
	obs.obs_leave_graphics()

	if data.effect == nil then
		obs.script_log(obs.LOG_ERROR, "Mirror: shader failed to compile")
		info.destroy(data)
		return nil
	end

	info.update(data, settings)
	return data
end

info.destroy = function(data)
	if data.effect ~= nil then
		obs.obs_enter_graphics()
		obs.gs_effect_destroy(data.effect)
		obs.obs_leave_graphics()
		data.effect = nil
	end
end

info.get_defaults = function(settings)
	obs.obs_data_set_default_int(settings, "mode", 0)
	obs.obs_data_set_default_double(settings, "pivot_x", 50.0)
	obs.obs_data_set_default_double(settings, "pivot_y", 50.0)
	obs.obs_data_set_default_double(settings, "angle", 0.0)
	obs.obs_data_set_default_int(settings, "segments", 6)
	obs.obs_data_set_default_bool(settings, "clip_outside", true)
end

info.get_properties = function(data)
	local props = obs.obs_properties_create()

	local m = obs.obs_properties_add_list(props, "mode", "Mode",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	obs.obs_property_list_add_int(m, "Left to right",  0)
	obs.obs_property_list_add_int(m, "Right to left",  1)
	obs.obs_property_list_add_int(m, "Top to bottom",  2)
	obs.obs_property_list_add_int(m, "Bottom to top",  3)
	obs.obs_property_list_add_int(m, "Quad",           4)
	obs.obs_property_list_add_int(m, "Kaleidoscope",   5)

	obs.obs_properties_add_float_slider(props, "pivot_x", "Mirror X (%)", 0.0, 100.0, 0.1)
	obs.obs_properties_add_float_slider(props, "pivot_y", "Mirror Y (%)", 0.0, 100.0, 0.1)
	obs.obs_properties_add_float_slider(props, "angle",   "Angle",     -180.0, 180.0, 0.1)
	obs.obs_properties_add_int_slider(props,   "segments","Segments",       2,    32, 1)
	obs.obs_properties_add_bool(props, "clip_outside", "Transparent outside frame")

	return props
end

info.update = function(data, settings)
	data.mode     = obs.obs_data_get_int(settings, "mode")
	data.pivot_x  = obs.obs_data_get_double(settings, "pivot_x") / 100.0
	data.pivot_y  = obs.obs_data_get_double(settings, "pivot_y") / 100.0
	data.angle    = obs.obs_data_get_double(settings, "angle")
	data.segments = obs.obs_data_get_int(settings, "segments")
	data.clip     = obs.obs_data_get_bool(settings, "clip_outside") and 1.0 or 0.0
end

info.video_render = function(data, effect)
	if data.effect == nil then
		obs.obs_source_skip_video_filter(data.source)
		return
	end

	local target = obs.obs_filter_get_target(data.source)
	local w = 1
	local h = 1
	if target ~= nil then
		w = obs.obs_source_get_base_width(target)
		h = obs.obs_source_get_base_height(target)
	end
	if w == 0 or h == 0 then
		obs.obs_source_skip_video_filter(data.source)
		return
	end
	data.width  = w
	data.height = h

	-- NO_DIRECT_RENDERING: the shader samples arbitrary coordinates, so the
	-- source has to be rendered to a texture first.
	if not obs.obs_source_process_filter_begin(data.source, obs.GS_RGBA,
			obs.OBS_NO_DIRECT_RENDERING) then
		return
	end

	obs.gs_effect_set_int(data.p_mode, data.mode)
	obs.gs_effect_set_float(data.p_pivot_x, data.pivot_x)
	obs.gs_effect_set_float(data.p_pivot_y, data.pivot_y)
	obs.gs_effect_set_float(data.p_angle, data.angle)
	obs.gs_effect_set_float(data.p_aspect, w / h)
	obs.gs_effect_set_int(data.p_seg, data.segments)
	obs.gs_effect_set_float(data.p_clip, data.clip)

	obs.obs_source_process_filter_end(data.source, data.effect, w, h)
end

function script_description()
	return "<b>Mirror</b><br>Adds a Mirror filter to any source: " ..
	       "horizontal / vertical / quad folds with a draggable, rotatable " ..
	       "mirror line, plus a kaleidoscope mode."
end

function script_load(settings)
	obs.obs_register_source(info)
end
