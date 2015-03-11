#!/usr/bin/ruby

require 'rubygems'
require 'RMagick'
include Magick

ARTWORKS = [
            #
            # default
            #
            { src_file:          'icon_512x512.png',
              target_resolution: '512x512',
              image_type:        'icon',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '320x480',
              image_type:        'splash',
            },

            #
            # iOS
            #
            { src_file:          'icon_512x512.png',
              target_resolution: '57x57',
              image_type:        'icon',
              platform:          'ios',
              comment:           'iPhone & iPod Touch non retina iOS6',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '114x114',
              image_type:        'icon',
              platform:          'ios',
              comment:           'iPhone & iPod Touch retina iOS6',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '72x72',
              image_type:        'icon',
              platform:          'ios',
              comment:           'iPad non retina iOS6',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '144x144',
              image_type:        'icon',
              platform:          'ios',
              comment:           'iPad retina iOS6',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '76x76',
              image_type:        'icon',
              platform:          'ios',
              comment:           'iPad non retina iOS7',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '152x152',
              image_type:        'icon',
              platform:          'ios',
              comment:           'iPad retina iOS7',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '60x60',
              image_type:        'icon',
              platform:          'ios',
              comment:           'iPhone & iPod Touch non retina iOS7',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '120x120',
              image_type:        'icon',
              platform:          'ios',
              comment:           'iPhone & iPod Touch retina iOS7',
            },

            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '320x480',
              image_type:        'splash',
              platform:          'ios',
              comment:           'iPhone & iPod Touch non retina',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '640x960',
              image_type:        'splash',
              platform:          'ios',
              comment:           'iPhone & iPod Touch retina 4-',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '640x1136',
              image_type:        'splash',
              platform:          'ios',
              comment:           'iPhone & iPod Touch retina 5+',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '768x1024',
              image_type:        'splash',
              platform:          'ios',
              comment:           'iPad non retina',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '1024x768',
              image_type:        'splash',
              platform:          'ios',
              comment:           'iPad non retina',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '1536x2048',
              image_type:        'splash',
              platform:          'ios',
              comment:           'iPad retina',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '2048x1536',
              image_type:        'splash',
              platform:          'ios',
              comment:           'iPad retina',
            },
            
            #
            # Android
            #
            { src_file:          'icon_512x512.png',
              target_resolution: '36x36',
              image_type:        'icon',
              platform:          'android',
              extra_parms:       'gap:qualifier="ldpi"',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '48x48',
              image_type:        'icon',
              platform:          'android',
              extra_parms:       'gap:qualifier="mdpi"',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '72x72',
              image_type:        'icon',
              platform:          'android',
              extra_parms:       'gap:qualifier="hdpi"',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '96x96',
              image_type:        'icon',
              platform:          'android',
              extra_parms:       'gap:qualifier="xhdpi"',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '144x144',
              image_type:        'icon',
              platform:          'android',
              extra_parms:       'gap:qualifier="xxhdpi"',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '192x192',
              image_type:        'icon',
              platform:          'android',
              extra_parms:       'gap:qualifier="xxxhdpi"',
            },

            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '200x320',
              image_type:        'splash',
              platform:          'android',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '320x480',
              image_type:        'splash',
              platform:          'android',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '480x800',
              image_type:        'splash',
              platform:          'android',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '720x1280',
              image_type:        'splash',
              platform:          'android',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '320x200',
              image_type:        'splash',
              platform:          'android',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '480x320',
              image_type:        'splash',
              platform:          'android',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '800x480',
              image_type:        'splash',
              platform:          'android',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '1280x720',
              image_type:        'splash',
              platform:          'android',
            },
            #
            # Blackberry
            #
            { src_file:          'icon_512x512.png',
              target_resolution: '80x80',
              image_type:        'icon',
              platform:          'blackberry',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '80x80',
              image_type:        'icon',
              platform:          'blackberry',
              extra_parms:       'gap:state="hover"',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '768x1024',
              image_type:        'splash',
              platform:          'blackberry',
            },
            #
            # Winphone
            #
            { src_file:          'icon_512x512.png',
              target_resolution: '57x57',
              image_type:        'icon',
              platform:          'winphone',
            },
            { src_file:          'icon_512x512.png',
              target_resolution: '72x72',
              image_type:        'icon',
              platform:          'winphone',
              extra_parms:       'gap:role="background"',
            },
            { src_file:          'splash_screen_720x1280.png',
              target_resolution: '480x800',
              image_type:        'splash',
              platform:          'winphone',
            },
           ]

IMAGE_BASE_DIR = '/home/geopeers/phonegap/geopeers'

def process_image (image_info)
  src_image_file = IMAGE_BASE_DIR + '/images/' + image_info[:src_file]
  src_img = Magick::Image::read(src_image_file)[0]

  # scale src_img down so it fits within target_resolution
  
  (dst_width, dst_height) = image_info[:target_resolution].split(/x/)
  x_scale = dst_width.to_f  / src_img.columns.to_f
  y_scale = dst_height.to_f / src_img.rows.to_f
  min_scale = [x_scale,y_scale].min
  src_img_scaled = src_img.resize(min_scale)
  if (x_scale == y_scale)
    dst_img = src_img_scaled
  else
    # src and dst have different aspect ratios
    # create a white image with the dst dimensions
    dst_img = Magick::ImageList.new
    dst_img.new_image(dst_width.to_i, dst_height.to_i) {
      self.background_color = 'white'
    }
    # place the scaled src image on top of the white background
    dst_img.composite!(src_img_scaled,CenterGravity,OverCompositeOp)
  end
  dst_file = 'images/res/'
  if (image_info[:platform])
    dst_file += image_info[:platform] + '/'
  end
  dst_file += image_info[:image_type] + '_' + image_info[:target_resolution] + File.extname(src_image_file)
  dst_img.write(IMAGE_BASE_DIR + '/' + dst_file)

  if (image_info[:image_type] == 'icon')
    config_ent = '<icon'
  elsif (image_info[:image_type] == 'splash')
    config_ent = '<gap:splash'
  else
    return
  end
  config_ent += " src=\"#{dst_file}\""
  if (image_info[:platform])
    config_ent += " gap:platform=\"#{image_info[:platform]}\""
  end
  config_ent += " width=\"#{dst_width}\""
  config_ent += " height=\"#{dst_height}\""
  if (image_info[:extra_parms])
    config_ent += ' '
    config_ent += image_info[:extra_parms]
  end
  config_ent += " />"
  if (image_info[:comment])
    config_ent += ' <!-- '
    config_ent += image_info[:comment]
    config_ent += ' -->'
  end
  config_ent
end

def process_artworks (artworks)
  artworks.each do |image_info|
    config_ent = process_image(image_info)
    puts config_ent
  end
end

process_artworks(ARTWORKS)
