# google_mlkit_text_recognition 0.13.0 的 initialize 引用了按需语种包
# （中文等 script recognizer），这些类不在基础依赖中，R8 压缩时忽略即可。
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
