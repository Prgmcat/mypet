# flutter_local_notifications persists scheduled notifications with Gson.
# R8 strips TypeToken generic signatures, which makes cancelAll() throw
# "TypeToken must be created with a type argument" in release builds.
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
