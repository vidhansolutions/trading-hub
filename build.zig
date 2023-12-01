const std = @import("std");


pub fn build(b: *std.build.Builder) !void {
   // _ = b.standardTargetOptions(.{});


  //   var target = b.standardTargetOptions(.{});
//     var optimize = b.standardOptimizeOption(.{});
//     const RestLib = b.addSharedLibrary(.{
//                 .name="RestAPI",
//                 .root_source_file = std.Build.FileSource.relative("./Rest/API/types.zig"),
//                 .target = target,
//                 .optimize= optimize
//             });


// //    b.installArtifact(RestLib);
//     var module = b.createModule(.{
//         .source_file = std.Build.FileSource.relative("Rest/API/types.zig")
//     });

//  RestLib.addModule("Rest",module);
//  b.installArtifact(RestLib);
//             const main_tests = b.addTest(.{
//                 .root_source_file = .{ .path = "Rest/API/Tests/types.zig" },
//                 .target = target,
//                 .optimize = optimize,
//             });

//     main_tests.addModule("Rest",module);
//     const run_main_tests = b.addRunArtifact(main_tests);
//             const test_step = b.step("test", "Run library tests");
//             test_step.dependOn(&run_main_tests.step);

    //try buildRestAPI(b,&target,&optimize);
    //const RestAPI = b.step("RestAPI", "this will build REST API independently");
    //const RestAPITest = b.step("runRestAPITest", "this will run test for Rest API");
    //RestAPITest.dependOn();
    //try modules(b, &target, &optimize);

    try projectStructure(b);
}

fn projectStructure(b: *std.build.Builder) !void {


    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var allocator = arena.allocator();

    var map = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer map.deinit();

    var dir = try std.fs.cwd().openIterableDir(".", .{});
    defer dir.close();

    var walker = try dir.walk(allocator);

    while(try walker.next()) |item|{
        if(isValidPath(item.path)){
            if(item.kind == std.fs.IterableDir.Entry.Kind.directory){
                // we need to check if the directory is in the dictionary already
                if (map.get(item.path) == null ){
                    var list = std.ArrayList([]const u8).init(allocator);
                    try map.put(item.path, list);
                    std.debug.print("new directory: {s}\n",.{item.path});
                    //std.debug.print("new list address: {*}\n",.{try list});
                }
                continue;
                //std.debug.print("directory: {s}\n",.{item.path});
            }
            if (item.kind == std.fs.IterableDir.Entry.Kind.file){
                const filePath = try removeFileFromPath(item.path,item.basename);
                if (map.getPtr(filePath)) |fileList|{
                    std.debug.print("new file added {s} to directory: {s}\n",.{item.basename,filePath});
                    try fileList.append(try std.mem.Allocator.dupe(allocator, u8, item.basename));
                    //try map.put(filePath,fileList.*);
                    //printDirectoryFiles(filePath,map);
                }
               // std.debug.print("file: {s}\n",.{filePath});
            }
            //std.debug.print("{s}\n",.{item.path});
        }
    }
    //printProject(map);
    try buildProject(b,&map);
}

fn buildProject(b: *std.build.Builder, project: *std.StringHashMap(std.ArrayList([]const u8))) !void {

    var target = b.standardTargetOptions(.{});
    var optimize = b.standardOptimizeOption(.{});

    var iter = project.*.iterator();
    while (iter.next()) |pkg| {
        // we should check if package has Test directory
        const pkgName = pkg.key_ptr.*;
        const pkgTest = try stringConcat(pkgName, "/Tests");
        // we get the modules that have a test file in the Tests folder
        if(project.get(pkgTest)) |modules| {
            std.debug.print("we have Test Directory at: {s}\n",.{pkgTest});
            // we have to check if the file with the same name is available in both directory
            for (modules.items) |moduleName|{
                std.debug.print("create module {s}\n",.{pkgName});
                const module = b.createModule(.{
                    .source_file = std.Build.FileSource.relative(try stringConcat(pkgName,
                                                                                  try stringConcat("/",moduleName)))
                });
                std.debug.print("adding tests for {s}.\n",.{moduleName});
                const testModule = b.addTest(.{
                    .root_source_file = .{ .path = try stringConcat(pkgTest,
                                                                    try stringConcat("/",moduleName)) },
                    .target = target,
                    .optimize = optimize,
                });
                std.debug.print("adding module to the test for import purpose\n",.{});
                testModule.addModule(pkgName,module);
                const tests = b.addRunArtifact(testModule);
                //_ = b.addInstallArtifact(tests, .{});
                const test_step = b.step(try stringConcat(try stringConcat("run", moduleName), "Tests"), "Run library tests");
                test_step.dependOn(&tests.step);
                // add test to the default build process so don't need to call the specific test
                std.debug.print("runing test for module {s}\n",.{moduleName});
                b.default_step.dependOn(test_step);
            }
        }
    }
}


fn printProject(map: std.StringHashMap(std.ArrayList([]const u8))) void{
    std.debug.print("===============================================\n",.{});
    var it = map.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        std.debug.print("{s}\n",.{key});
        if (map.getPtr(key)) |list|{
            for(list.items) |file|{
                std.debug.print("{s}\n",.{file});
            }
        }
    }
}

fn printDirectoryFiles(directory: [] const u8, map: std.StringHashMap(std.ArrayList([]const u8))) void{
    if (map.get(directory)) |files| {
        for(files.items) |file|{
            std.debug.print("file: {s}\n",.{file});
        }
    }
}

fn isValidPath(path: []const u8) bool {
    var ignoreList = [_][] const u8 {"zig-cache", "zig-out", ".idea", ".git", "build.zig", ".md", "~"};
    for (ignoreList) |item|{
       // std.debug.print("{s}\n", .{item});
        if(std.mem.indexOf(u8,path,item) != null){
            //std.debug.print("from validate function: {s}\n", .{item});
            return false;
        }
    }
    return true;
}

fn removeFileFromPath(path: []const u8, fileName: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8,path,fileName)) |index| {
        // var builder = std.ArrayList(u8).init(std.heap.page_allocator);
        //defer builder.deinit();
        const newPath = path[0..index-1];
        //std.debug.print("new path {s}\n",.{newPath});
        return newPath;
    }
    return error.NothingChanged;
}

fn stringConcat(string1: []const u8,string2: []const u8) ![]const u8{
    var builder = std.ArrayList(u8).init(std.heap.page_allocator);
    defer builder.deinit();
    try builder.appendSlice(string1);
    try builder.appendSlice(string2);
    const result = try std.heap.page_allocator.dupe(u8, builder.items);
    return result;
}
