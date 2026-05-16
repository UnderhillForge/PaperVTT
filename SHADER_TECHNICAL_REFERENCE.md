# Stylized Grass Shader - Technical Reference

## Shader: res://shaders/grass.gdshader

### Purpose
High-quality stylized grass rendering with advanced wind simulation, designed for use with MultiMesh instances. Each blade is a simple quad that's deformed via vertex shader for maximum efficiency.

### Uniforms (Inspector / Code Accessible)

#### Wind Parameters
```glsl
uniform float wind_strength : hint_range(0.0, 2.0) = 0.5;
uniform float wind_speed : hint_range(0.1, 5.0) = 1.0;
uniform float wind_direction_deg : hint_range(0.0, 359.0) = 35.0;
```
- **wind_strength**: Amplitude of wind displacement (0.5 = gentle, 2.0 = violent)
- **wind_speed**: Time scale of wind animation (1.0 = normal, 2.0 = fast)
- **wind_direction_deg**: Primary wind direction in degrees (0=+X, 90=+Z)

#### Grass Shape Parameters
```glsl
uniform float grass_height : hint_range(0.1, 3.0) = 0.65;
uniform float sway_amount : hint_range(0.0, 1.0) = 0.3;
```
- **grass_height**: Blade length scale (0.65 = medium, 3.0 = very tall)
- **sway_amount**: Independent swaying motion (0.0 = stiff, 1.0 = very swayy)

#### Color Parameters
```glsl
uniform vec3 base_color : source_color = Color(0.12, 0.22, 0.10, 1.0);
uniform vec3 tip_color : source_color = Color(0.40, 0.49, 0.28, 1.0);
```
- **base_color**: Color at blade base (typically darker)
- **tip_color**: Color at blade tip (typically lighter)
- Linear interpolation creates natural gradient

#### Noise Parameters
```glsl
uniform sampler2D color_noise : hint_default_white;
uniform float noise_scale : hint_range(1.0, 100.0) = 20.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.15;
```
- **color_noise**: Texture sampler (can be white or Perlin noise)
- **noise_scale**: World-space frequency (20 = tiling every 20 units)
- **noise_strength**: Blend amount of noise into color (0.0 = no variation)

### Vertex Shader Algorithm

#### 1. Position Normalization
```
Input VERTEX is a quad (-0.5 to 0.5 in X, 0.0 to 1.0 in Y)
Offset by +0.5 in Y to map to 0.0-1.0 range
Calculate height parameter t = clamp(Y, 0, 1)
```

#### 2. Per-Blade Randomization
```
Get world position of blade base
Generate 3 random values (r0, r1, r2) using hash2(world_pos * seed)
These seed blade-specific variations:
  - r0: blade rotation and width
  - r1, r2: wind phase and motion characteristics
```

#### 3. Blade Scale
```
Height variation: 0.35 to 1.0x (prevents uniform look)
Width variation: 0.042 to 0.068 units (maintains variety)
Taper: Gradually narrow from base to tip (1.0 - t * 0.80)
```

#### 4. Wind Deformation

**Main Wind Component:**
- Primary direction from wind_direction_deg
- Two sine waves at different frequencies for natural motion
- Space-varying phase based on blade position
- Creates flowing, directional wind effect

**Secondary Components:**
- Random wind direction adds turbulence
- Independent wave frequency creates micro-gusts
- Combines into smooth, organic motion

**Sway Effect:**
- Low-frequency sine wave (0.3 * wind_speed)
- Adds gentle rocking motion independent of wind
- Blends smoothly with wind deformation

#### 5. Blade Bending Physics
```
droop = height-based gravity effect (stronger at tip)
bend = wind-force deformation (scaled by stiffness)
steer = rotation adjustment for wind direction

Apply using axis-angle rotation matrices
Bend axis perpendicular to wind direction
Result: Natural, organic blade bending
```

### Fragment Shader Algorithm

#### 1. Height-based Coloring
```
t = 1.0 - blade_height_t (inverted so 0=tip, 1=base)
t2 = t * t (quadratic falloff)
base_color mixed toward tip_color using t2
Result: Smooth gradient from base to tip
```

#### 2. Noise Coloring
```
Sample color_noise at world position / noise_scale
Modulate between 1.0 and noise_sample using noise_strength
Multiplies into base color for variation
```

#### 3. Ambient Occlusion
```
AO = mix(0.22, 1.0, t2)
Darkens base, brightens tip
Adds depth without complex calculation
```

#### 4. Stylization
```
Quantize to 3 tonal levels for graphic novel look
Apply tonal shading (0.72 to 1.08 range)
Desaturate by 22% for natural appearance
Result: Stylized but not cartoonish
```

#### 5. Material Properties
```
ROUGHNESS = 0.96 at base, 0.62 at tip (grass is rough)
SPECULAR = 0.0 (grass doesn't shine)
Final color output with applied lighting
```

### Varying Values
```glsl
varying vec3 worldPos;       // World position for noise sampling
varying float blade_height_t; // Height along blade (0=base, 1=tip)
```

### Mathematical Foundation

#### Hash Function (Pseudo-random)
```glsl
float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));  // Prime multiplication for distribution
    p += dot(p, p + 19.19);               // Self-referential folding
    return fract(p.x * p.y);              // Final mix
}
```
Generates deterministic randomness based on input position. Same position always gives same value (important for temporal coherence).

#### Rotation Matrices
```glsl
rot_y(angle)      // Rotation around Y axis
rot_axis(axis, a) // Rotation around arbitrary axis

Used for blade orientation and wind deformation
Matrix composition allows elegant physics-like bending
```

### Performance Characteristics

- **Vertex Shader**: ~25-40 instructions per vertex
- **Fragment Shader**: ~15-20 instructions per pixel
- **Texture Lookups**: 2 (noise sample, normal maps if used)
- **No Branching**: Runs efficiently on mobile
- **Time-Driven**: Expensive operations only in vertex shader

### Visual Quality Levers

| Parameter | Low | Medium | High |
|-----------|-----|--------|------|
| wind_strength | 0.1 | 0.5 | 2.0 |
| wind_speed | 0.1 | 1.0 | 5.0 |
| grass_height | 0.2 | 0.65 | 2.0 |
| sway_amount | 0.0 | 0.3 | 1.0 |
| noise_strength | 0.0 | 0.15 | 0.5 |

### Recommended Presets

**"Gentle Breeze":**
```
wind_strength = 0.3
wind_speed = 0.5
grass_height = 0.5
sway_amount = 0.2
noise_strength = 0.1
```

**"Flowing Meadow":**
```
wind_strength = 0.7
wind_speed = 1.0
grass_height = 0.7
sway_amount = 0.4
noise_strength = 0.2
```

**"Stormy":**
```
wind_strength = 1.5
wind_speed = 2.0
grass_height = 0.4
sway_amount = 0.1
noise_strength = 0.3
```

**"Stylized/Still":**
```
wind_strength = 0.0
wind_speed = 0.0
grass_height = 0.6
sway_amount = 0.0
noise_strength = 0.25
```

### Color Palette Recommendations

**Spring Green:**
- Base: #0f2008
- Tip: #4d7a3d

**Summer Lush:**
- Base: #1f3818
- Tip: #667c47

**Autumn:**
- Base: #3d2914
- Tip: #a68a4a

**Winter Dry:**
- Base: #2d2820
- Tip: #8a8470

### Comparison to Original Shader

| Aspect | Original | Enhanced |
|--------|----------|----------|
| Wind Model | Simple sine | Multi-layer oscillation |
| Sway | None | Configurable |
| Color Variation | Basic mix | Noise-based sampling |
| Stylization | Minimal | Tonal compression + AO |
| Parameters | 6 | 10 |
| Visual Quality | Good | High |
| Performance Impact | Minimal | None (same architecture) |

### Known Limitations

1. **No Per-Blade Wind Response**: All blades bend uniformly (acceptable for dense grass)
2. **No Blade Collision**: Blades don't interact with objects (could add via sdf)
3. **No Self-Shadowing**: Would require depth pass
4. **2D Noise**: Uses worldPos.xz, ignores height (sufficient for ground grass)

### Future Enhancements

1. Add vertex paint blending for biome transitions
2. Animate noise texture for dappled shadows
3. Add wind direction texture for turbulence fields
4. Support indirect lighting from lightmaps
5. Add optional tri-planar mapping for slopes
