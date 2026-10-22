package vn.czn.viethoa.czn_patcher;

/** Only migrate the two known official shared URLs; custom channels stay intact. */
public final class UpdateChannel {
    private static final String BASE="https://github.com/doubleD1302/CZN-VH/releases/";
    public static final String SHARED=BASE+"latest/download/channel.json";
    public static final String LOCAL=BASE+"latest/download/localadb-channel.json";
    private UpdateChannel() {}
    public static String resolve(String value,boolean local) {
        if(value==null||value.trim().isEmpty())return local?LOCAL:SHARED;
        if(local&&value.equals(SHARED))return LOCAL;
        if(local&&value.equals(BASE+"download/releases-1.0/channel.json"))
            return BASE+"download/releases-1.0/localadb-channel.json";
        return value;
    }
    /** A cached shared-channel APK must not be offered by the Local ADB client. */
    public static boolean acceptsApp(String route,String appUrl,boolean local) {
        if(!local||!(route.equals(LOCAL)||route.equals(BASE+"download/releases-1.0/localadb-channel.json")))return true;
        if(!appUrl.startsWith(BASE+"download/"))return true;
        String name=appUrl.substring(appUrl.lastIndexOf('/')+1);
        return !name.endsWith(".apk")||name.startsWith("CZN_VietHoa_LocalADB_");
    }
}
