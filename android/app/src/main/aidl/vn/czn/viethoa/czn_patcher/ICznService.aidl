package vn.czn.viethoa.czn_patcher;
import android.os.ParcelFileDescriptor;
import vn.czn.viethoa.czn_patcher.IPatchProgress;
interface ICznService {
 String inspect(String packageName) = 0;
 String install(String packageName, in ParcelFileDescriptor zip, IPatchProgress progress) = 1;
 String restore(String packageName, IPatchProgress progress) = 2;
 void destroy() = 16777114;
}
