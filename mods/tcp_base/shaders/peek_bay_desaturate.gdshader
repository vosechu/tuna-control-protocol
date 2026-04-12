shader_type canvas_item;

uniform float desaturation : hint_range(0.0, 1.0) = 0.65;
uniform float brightness : hint_range(0.0, 1.0) = 0.8;

void fragment() {
    vec4 src = texture(TEXTURE, UV);
    float luma = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 desat = mix(src.rgb, vec3(luma), desaturation);
    COLOR = vec4(desat * brightness, src.a);
}
