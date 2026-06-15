import java.io.*;
class BugPathTraversal {
  File open(String name) {
    return new File("/data/" + name);   // user-controlled name -> traversal
  }
}
