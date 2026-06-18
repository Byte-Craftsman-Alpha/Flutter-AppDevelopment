# 1. Protect the entire models package completely from renaming or optimization
-keep class com.example.flutter_application_1.models.** { *; }

# 2. Prevent R8 from stripping away serialization methods or fields in any file
-keepclassmembers class com.example.flutter_application_1.models.** {
    <fields>;
    <methods>;
}

# 3. Explicitly preserve JSON and Map parsing conversion utilities
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses, SourceFile, LineNumberTable

# 4. Prevent Supabase/Postgrest underlying response models from breaking
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**