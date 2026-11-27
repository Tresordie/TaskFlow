# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(audio_decoder_library VERSION 0.0.1 LANGUAGES C)

add_library(audio_decoder SHARED
  "audio_decoder.c"
)

set_target_properties(audio_decoder PROPERTIES
  PUBLIC_HEADER audio_decoder.h
  OUTPUT_NAME "audio_decoder"
)

target_compile_definitions(audio_decoder PUBLIC DART_SHARED_LIB)

if (MSVC)
  # Sources are UTF-8 (Chinese error messages); without /utf-8 MSVC on a
  # GBK system (codepage 936) misreads them → "newline in constant" errors.
  target_compile_options(audio_decoder PRIVATE "/utf-8")
endif()

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(audio_decoder PRIVATE "-Wl,-z,max-page-size=16384")
endif()
