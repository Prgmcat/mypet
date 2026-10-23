# google_mlkit_text_recognition references every script's options class, but
# the app only ships the Chinese model. R8 treats the compileOnly references as
# missing classes in release builds.
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# flutter_local_notifications persists scheduled notifications with Gson.
# R8 strips TypeToken generic signatures, which makes cancelAll() throw
# "TypeToken must be created with a type argument" in release builds.
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
