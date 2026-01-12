package {
    import flash.display.Bitmap;
    import flash.display.Loader;
    import flash.events.Event;
    import flash.events.HTTPStatusEvent;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;
    import flash.net.URLRequestMethod;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;
    import flash.utils.Timer;
    import flash.events.TimerEvent;

    /**
     * Простое кеширование картинок:
     * - Не качаем один и тот же URL повторно.
     * - Храним байты в памяти и на диске (ApplicationStorageDirectory/images).
     * - Возвращаем Bitmap через callback.
     */
    public class ImageCache {
        private static const USE_MEMORY_CACHE:Boolean = false;
        private static const PREFETCH_MAX_CONCURRENT:int = 6;
        private static const DOWNLOAD_TIMEOUT_MS:int = 15000;
        private static var memoryCache:Dictionary = new Dictionary(); // url -> ByteArray
        private static var pending:Object = {}; // url -> Array of callbacks waiting
        private static var sizeIndex:Object = null; // url -> size
        private static var sizeIndexLoaded:Boolean = false;

        public static function getBitmap(url:String,
                                         onReady:Function,
                                         onError:Function = null):void {
            if (!url || url.length == 0) {
                if (onError != null) onError("Empty URL");
                return;
            }

            // already in memory
            if (USE_MEMORY_CACHE && memoryCache[url]) {
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
                    var expectedSize:* = getExpectedSize(url);
                    var localSize:Number = localFile.size;
                    var hasExpected:Boolean = (expectedSize is Number) && expectedSize > 0;

                    if (localSize <= 0 || (hasExpected && localSize != expectedSize)) {
                        try { localFile.deleteFile(); } catch (_:Error) {}
                    } else {
                        if (!hasExpected) {
                            updateSizeIndex(url, localSize);
                        }
                        loadBitmapFromFile(localFile, onReady, onError);
                        return;
                    }

                    if (localFile.exists) {
                        localSize = localFile.size;
                        if (localSize > 0 && (!hasExpected || localSize == expectedSize)) {
                            if (!hasExpected) {
                                updateSizeIndex(url, localSize);
                            }
                            loadBitmapFromFile(localFile, onReady, onError);
                            return;
                        }
                    }
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
                trace("[ImageCache] Prefetch complete: 0");
                if (onComplete != null) onComplete();
                return;
            }

            var remaining:int = queue.length;
            var total:int = queue.length;
            var index:int = 0;
            var inFlight:int = 0;

            var done:Function = function():void {
                remaining--;
                inFlight--;
                var loaded:int = total - remaining;
                if (remaining >= 0 && remaining < total) {
                    trace("[ImageCache] Prefetch progress: " + loaded + " loaded, " + remaining + " remaining");
                }
                if (remaining <= 0) {
                    trace("[ImageCache] Prefetch complete: " + total);
                    if (onComplete != null) onComplete();
                    return;
                }
                pump();
            };

            var pump:Function = function():void {
                while (inFlight < PREFETCH_MAX_CONCURRENT && index < queue.length) {
                    var url:String = queue[index++];
                    inFlight++;
                    prefetchOne(url, done);
                }
            };

            pump();
        }

        public static function purgeUrls(urls:Array):void {
            if (!urls || urls.length == 0) {
                return;
            }

            var unique:Object = {};
            var list:Array = [];
            for each (var raw:* in urls) {
                var u:String = String(raw);
                if (u && u.length > 0 && !unique[u]) {
                    unique[u] = true;
                    list.push(u);
                }
            }

            if (list.length == 0) return;

            loadSizeIndex();

            for each (var url:String in list) {
                if (USE_MEMORY_CACHE && memoryCache[url]) {
                    delete memoryCache[url];
                }
                if (sizeIndex && sizeIndex.hasOwnProperty(url)) {
                    delete sizeIndex[url];
                }
                var localFile:File = resolveLocalFile(url);
                if (localFile.exists) {
                    try { localFile.deleteFile(); } catch (_:Error) {}
                }
            }

            saveSizeIndex();
        }

        private static function download(url:String,
                                         onReady:Function,
                                         onError:Function):void {
            var loader:URLLoader = new URLLoader();
            loader.dataFormat = URLLoaderDataFormat.BINARY;
            var finished:Boolean = false;
            var timer:Timer = new Timer(DOWNLOAD_TIMEOUT_MS, 1);

            pending[url] = [{ ready: onReady, error: onError }];

            var finish:Function = function(data:ByteArray, err:String):void {
                if (finished) return;
                finished = true;
                timer.stop();
                notify(url, data, err);
            };

            loader.addEventListener(Event.COMPLETE, function(e:Event):void {
                var data:ByteArray = loader.data as ByteArray;
                if (!data) {
                    finish(null, "Empty data after load");
                    return;
                }

                var cached:ByteArray = new ByteArray();
                data.position = 0;
                cached.writeBytes(data);
                cached.position = 0;

                if (USE_MEMORY_CACHE) {
                memoryCache[url] = cached;
                }

                // save to disk for последующего запуска
                try {
                    saveBytes(resolveLocalFile(url), cached);
                    updateSizeIndex(url, cached.length);
                } catch (saveErr:Error) {
                    trace("[ImageCache] Не удалось сохранить на диск:", saveErr.message);
                }

                finish(cached, null);
            });

            loader.addEventListener(IOErrorEvent.IO_ERROR, function(err:IOErrorEvent):void {
                finish(null, err.text);
            });

            try {
                loader.load(new URLRequest(url));
            } catch (loadErr:Error) {
                finish(null, loadErr.message);
            }

            timer.addEventListener(TimerEvent.TIMER, function(_:TimerEvent):void {
                finish(null, "Download timeout");
            });
            timer.start();
        }

        private static function notify(url:String, data:ByteArray, error:String):void {
            var listeners:Array = pending[url] || [];
            delete pending[url];

            if (USE_MEMORY_CACHE && data != null && !memoryCache[url]) {
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

        private static function loadBitmapFromFile(file:File,
                                                   onReady:Function,
                                                   onError:Function):void {
            if (!file || !file.exists) {
                if (onError != null) onError("File not found");
                return;
            }

            var loader:Loader = new Loader();
            loader.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_:Event):void {
                var bmp:Bitmap = loader.content as Bitmap;
                if (bmp && onReady != null) {
                    bmp.smoothing = true;
                    onReady(bmp);
                } else if (onError != null) {
                    onError("Не удалось создать Bitmap из файла");
                }
            });
            loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(err:IOErrorEvent):void {
                if (onError != null) onError(err.text);
            });
            try {
                loader.load(new URLRequest(file.url));
            } catch (loadErr:Error) {
                if (onError != null) onError(loadErr.message);
            }
        }

        private static function resolveLocalFile(url:String):File {
            var folder:File = getImagesFolder();
            var fileName:String = url.replace(/[^A-Za-z0-9_.-]/g, "_");
            if (fileName.length > 120) {
                fileName = fileName.substr(fileName.length - 120);
            }
            return folder.resolvePath(fileName);
        }

        private static function prefetchOne(url:String, done:Function):void {
            if (!url || url.length == 0) {
                done();
                return;
            }

            if ((USE_MEMORY_CACHE && memoryCache[url]) || pending[url]) {
                done();
                return;
            }

            var localFile:File = resolveLocalFile(url);
            var localExists:Boolean = localFile.exists;
            var localSize:Number = localExists ? localFile.size : -1;
            var expected:* = getExpectedSize(url);
            var hasExpected:Boolean = (expected is Number) && expected > 0;

            if (localExists && localSize > 0 && hasExpected && localSize != expected) {
                try { localFile.deleteFile(); } catch (_:Error) {}
                localExists = localFile.exists;
                localSize = localExists ? localFile.size : -1;
            }

            if (localExists && localSize > 0) {
                if (hasExpected && localSize == expected) {
                    done();
                    return;
                }
                fetchRemoteSize(url, function(remoteSize:Number):void {
                    if (!isNaN(remoteSize) && remoteSize > 0) {
                        updateSizeIndex(url, remoteSize);
                        if (remoteSize == localSize) {
                            done();
                            return;
                        }
                        getBitmap(url, function(_:Bitmap):void { done(); }, function(_:String):void { done(); });
                        return;
                    }
                    // If size can't be checked, assume local file is up-to-date to avoid re-downloads.
                    done();
                });
                return;
            }

            getBitmap(url, function(_:Bitmap):void { done(); }, function(_:String):void { done(); });
        }

        private static function fetchRemoteSize(url:String, onResult:Function):void {
            var loader:URLLoader = new URLLoader();
            var req:URLRequest = new URLRequest(url);
            req.method = URLRequestMethod.HEAD;
            var finished:Boolean = false;
            var timeoutMs:int = 5000;
            var timer:Timer = new Timer(timeoutMs, 1);

            var finish:Function = function(size:Number):void {
                if (finished) return;
                finished = true;
                timer.stop();
                try { loader.close(); } catch (_:Error) {}
                onResult(size);
            };

            var parseHeaders:Function = function(headers:Array):Number {
                var size:Number = NaN;
                if (!headers) return size;
                for each (var h:URLRequestHeader in headers) {
                    if (h && h.name && h.name.toLowerCase() == "content-length") {
                        size = Number(h.value);
                        break;
                    }
                }
                return size;
            };

            loader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, function(e:HTTPStatusEvent):void {
                finish(parseHeaders(e.responseHeaders));
            });
            loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(e:HTTPStatusEvent):void {
                if (finished) return;
                finish(parseHeaders(e.responseHeaders));
            });
            loader.addEventListener(IOErrorEvent.IO_ERROR, function(_:IOErrorEvent):void { finish(NaN); });
            loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(_:SecurityErrorEvent):void { finish(NaN); });

            try {
                loader.load(req);
            } catch (_:Error) {
                finish(NaN);
            }

            timer.addEventListener(TimerEvent.TIMER, function(_:TimerEvent):void {
                finish(NaN);
            });
            timer.start();
        }

        private static function getImagesFolder():File {
            var folder:File = File.applicationStorageDirectory.resolvePath("images");
            if (!folder.exists) {
                try { folder.createDirectory(); } catch (e:Error) {}
            }
            return folder;
        }

        private static function getIndexFile():File {
            return getImagesFolder().resolvePath("index.json");
        }

        private static function loadSizeIndex():void {
            if (sizeIndexLoaded) return;
            sizeIndexLoaded = true;
            sizeIndex = {};
            var file:File = getIndexFile();
            if (!file.exists) return;
            try {
                var stream:FileStream = new FileStream();
                stream.open(file, FileMode.READ);
                var raw:String = stream.readUTFBytes(stream.bytesAvailable);
                stream.close();
                sizeIndex = JSON.parse(raw);
            } catch (e:Error) {
                sizeIndex = {};
            }
        }

        private static function saveSizeIndex():void {
            if (!sizeIndexLoaded || !sizeIndex) return;
            try {
                var file:File = getIndexFile();
                var stream:FileStream = new FileStream();
                stream.open(file, FileMode.WRITE);
                stream.writeUTFBytes(JSON.stringify(sizeIndex));
                stream.close();
            } catch (e:Error) {}
        }

        private static function getExpectedSize(url:String):* {
            loadSizeIndex();
            return sizeIndex ? sizeIndex[url] : null;
        }

        private static function updateSizeIndex(url:String, size:Number):void {
            if (!url || size <= 0) return;
            loadSizeIndex();
            sizeIndex[url] = size;
            saveSizeIndex();
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
