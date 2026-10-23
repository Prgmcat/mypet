# google_mlkit_text_recognition references every script's options class, but
# the app only ships the Chinese model. R8 treats the compileOnly references as
# missing classes in release builds.
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
