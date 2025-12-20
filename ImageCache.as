package {
    import flash.display.Bitmap;
    import flash.display.Loader;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.URLRequest;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;

    /**
     * Простое кеширование картинок:
     * - Не качаем один и тот же URL повторно.
     * - Храним байты в памяти и на диске (ApplicationStorageDirectory/images).
     * - Возвращаем Bitmap через callback.
     */
    public class ImageCache {
        private static var memoryCache:Dictionary = new Dictionary(); // url -> ByteArray
        private static var pending:Object = {}; // url -> Array of callbacks waiting

        public static function getBitmap(url:String,
                                         onReady:Function,
                                         onError:Function = null):void {
            if (!url || url.length == 0) {
                if (onError != null) onError("Empty URL");
                return;
            }

            // already in memory
            if (memoryCache[url]) {
                provideBitmap(url, memoryCache[url] as ByteArray, onReady, onError);
                return;
            }

            // already loading -> queue callback
            if (pending[url]) {
                pending[url].push({ ready: onReady, error: onError });
                return;
            }

            // check disk cache first
            var localFile:File = resolveLocalFile(url);
            if (localFile.exists) {
                try {
                    var bytes:ByteArray = readBytes(localFile);
                    memoryCache[url] = bytes;
                    provideBitmap(url, bytes, onReady, onError);
                    return;
                } catch (fileErr:Error) {
                    trace("[ImageCache] Ошибка чтения кеша с диска:", fileErr.message);
                }
            }

            // start download
            download(url, onReady, onError);
        }

        public static function prefetchUrls(urls:Array, onComplete:Function = null):void {
            if (!urls || urls.length == 0) {
                if (onComplete != null) onComplete();
                return;
            }

            var unique:Object = {};
            var queue:Array = [];
            for each (var raw:* in urls) {
                var u:String = String(raw);
                if (u && u.length > 0 && !unique[u]) {
                    unique[u] = true;
                    queue.push(u);
                }
            }

            if (queue.length == 0) {
                if (onComplete != null) onComplete();
                return;
            }

            var remaining:int = queue.length;
            var done:Function = function():void {
                remaining--;
                if (remaining <= 0 && onComplete != null) onComplete();
            };

            for each (var url:String in queue) {
                getBitmap(url, function(_:Bitmap):void { done(); }, function(_:String):void { done(); });
            }
        }

        private static function download(url:String,
                                         onReady:Function,
                                         onError:Function):void {
            var loader:URLLoader = new URLLoader();
            loader.dataFormat = URLLoaderDataFormat.BINARY;

            pending[url] = [{ ready: onReady, error: onError }];

            loader.addEventListener(Event.COMPLETE, function(e:Event):void {
                var data:ByteArray = loader.data as ByteArray;
                if (!data) {
                    notify(url, null, "Empty data after load");
                    return;
                }

                var cached:ByteArray = new ByteArray();
                data.position = 0;
                cached.writeBytes(data);
                cached.position = 0;

                memoryCache[url] = cached;

                // save to disk for последующего запуска
                try {
                    saveBytes(resolveLocalFile(url), cached);
                } catch (saveErr:Error) {
                    trace("[ImageCache] Не удалось сохранить на диск:", saveErr.message);
                }

                notify(url, cached, null);
            });

            loader.addEventListener(IOErrorEvent.IO_ERROR, function(err:IOErrorEvent):void {
                notify(url, null, err.text);
            });

            try {
                loader.load(new URLRequest(url));
            } catch (loadErr:Error) {
                notify(url, null, loadErr.message);
            }
        }

        private static function notify(url:String, data:ByteArray, error:String):void {
            var listeners:Array = pending[url] || [];
            delete pending[url];

            if (data != null && !memoryCache[url]) {
                memoryCache[url] = data;
            }

            for each (var item:Object in listeners) {
                if (data != null && item.ready != null) {
                    provideBitmap(url, data, item.ready as Function, item.error as Function);
                } else if (error != null && item.error != null) {
                    item.error(error);
                }
            }
        }

        private static function provideBitmap(url:String,
                                              bytes:ByteArray,
                                              onReady:Function,
                                              onError:Function):void {
            if (!bytes) {
                if (onError != null) onError("Empty bytes for url " + url);
                return;
            }

            var copy:ByteArray = new ByteArray();
            bytes.position = 0;
            copy.writeBytes(bytes);
            copy.position = 0;

            var loader:Loader = new Loader();
            loader.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_:Event):void {
                var bmp:Bitmap = loader.content as Bitmap;
                if (bmp && onReady != null) {
                    bmp.smoothing = true;
                    onReady(bmp);
                } else if (onError != null) {
                    onError("Не удалось создать Bitmap из " + url);
                }
            });
            loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(err:IOErrorEvent):void {
                if (onError != null) onError(err.text);
            });
            try {
                loader.loadBytes(copy);
            } catch (loadErr:Error) {
                if (onError != null) onError(loadErr.message);
            }
        }

        private static function resolveLocalFile(url:String):File {
            var folder:File = File.applicationStorageDirectory.resolvePath("images");
            if (!folder.exists) {
                try { folder.createDirectory(); } catch (e:Error) {}
            }
            var fileName:String = url.replace(/[^A-Za-z0-9_.-]/g, "_");
            if (fileName.length > 120) {
                fileName = fileName.substr(fileName.length - 120);
            }
            return folder.resolvePath(fileName);
        }

        private static function saveBytes(file:File, data:ByteArray):void {
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.WRITE);
            data.position = 0;
            stream.writeBytes(data, 0, data.length);
            stream.close();
        }

        private static function readBytes(file:File):ByteArray {
            var stream:FileStream = new FileStream();
            stream.open(file, FileMode.READ);
            var bytes:ByteArray = new ByteArray();
            stream.readBytes(bytes);
            stream.close();
            bytes.position = 0;
            return bytes;
        }
    }
}
