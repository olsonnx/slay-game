# Cloud shader source

Adapted from **Volumetric Raymarched (animated) Clouds v2**, by **thepathgame**:
https://godotshaders.com/shader/volumetric-raymarched-animated-clouds-v2/

The source page identifies its shader code as **CC0**:
https://creativecommons.org/publicdomain/zero/1.0/

The adaptation changes projection to orthographic rays, bounds the sample count,
adds stable volume lighting, and separates low-resolution cloud rendering from a
full-resolution depth mask. No source-page images or textures are included.
