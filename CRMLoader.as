package {
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.IOErrorEvent;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import CRMData;

    public class CRMLoader extends EventDispatcher {
        public static const DATA_UPDATED:String = "crmDataUpdated";

        private const API_KEY:String = "1212a891-b842-4d09-afe8-2aeb71761c73";
        private const API_LAYOUTS_URL:String = "https://data.crm-point.ru/layout";

        private var existingData:Object = {};
        private var crmLayouts:Array = [];
        private var resultData:Object = {};
        private var imagesToPrefetch:Object = {};

        public function CRMLoader() {
            super();
        }

        public function start():void {
            loadLocalJSON();
            loadLayouts();
        }

        private function loadLocalJSON():void {
            try {
                var file:File = File.applicationStorageDirectory.resolvePath("crm_data.json");
                if (!file.exists) {
                    trace("[CRMLoader] Локальный crm_data.json не найден! Будет использоваться пустой объект.");
                    existingData = {};
                    return;
                }

                var stream:FileStream = new FileStream();
                stream.open(file, FileMode.READ);
                var raw:String = stream.readUTFBytes(stream.bytesAvailable);
                stream.close();

                existingData = JSON.parse(raw);
                trace("[CRMLoader] Загружен локальный JSON, строк: " + ObjectKeys(existingData).length);

            } catch (e:Error) {
                trace("[CRMLoader] Ошибка чтения локального JSON: " + e.message);
                existingData = {};
            }
        }

        private function loadLayouts():void {
            var req:URLRequest = new URLRequest(API_LAYOUTS_URL);
            req.requestHeaders.push(new URLRequestHeader("Authorization", API_KEY));

            var loader:URLLoader = new URLLoader();
            loader.addEventListener(Event.COMPLETE, onLayoutsLoaded);
            loader.addEventListener(IOErrorEvent.IO_ERROR, onError);
            loader.load(req);
        }

        private function onLayoutsLoaded(e:Event):void {
            try {
                crmLayouts = JSON.parse(URLLoader(e.target).data) as Array;
                trace("[CRMLoader] Загружено объектов CRM: " + crmLayouts.length);
                mergeCRM();
            } catch (err:Error) {
                trace("[CRMLoader] Ошибка парсинга CRM: " + err.message);
            }
        }

        private function mergeCRM():void {
            imagesToPrefetch = {};

            for (var k:String in existingData) {
                resultData[k] = existingData[k];
            }

            var statusMap:Object = {
                "свободно": "Available",
                "бронь": "Reserved",
                "куплено": "Occupied",
                "закрыт к продаже": "Сlosed for sale",
                "available": "Available",
                "reserved": "Reserved",
                "occupied": "Occupied",
                "сlosed for sale": "Сlosed for sale"
            };

            for each (var apt:Object in crmLayouts) {
                if (!apt.hasOwnProperty("number")) {
                    trace("[CRMLoader] В CRM-объекте нет поля number — пропускаем элемент.");
                    continue;
                }

                var num:String = String(apt.number);

                if (!resultData.hasOwnProperty(num)) {
                    trace("[CRMLoader] Пропуск квартиры " + num + " — её нет в локальном JSON");
                    continue;
                }

                var old:Object = resultData[num];
                var updated:Object = {};

                for (var f:String in old) {
                    updated[f] = old[f];
                }

                if (apt.hasOwnProperty("status") && apt.status != null && String(apt.status) != "") {
                    var sKey:String = String(apt.status).toLowerCase();
                    if (statusMap.hasOwnProperty(sKey)) {
                        updated.status = statusMap[sKey];
                    } else {
                        updated.status = String(apt.status);
                    }
                }

                if (apt.hasOwnProperty("area") && apt.area !== null && apt.area !== undefined) {
                    updated.square = apt.area;
                }
                if (apt.hasOwnProperty("area_living") && apt.area_living !== null && apt.area_living !== undefined) {
                    updated.area_living = apt.area_living;
                }
                if (apt.hasOwnProperty("area_balcony") && apt.area_balcony !== null && apt.area_balcony !== undefined) {
                    updated.area_balcony = apt.area_balcony;
                }
                if (apt.hasOwnProperty("rooms") && apt.rooms !== null && apt.rooms !== undefined) {
                    updated.rooms = apt.rooms;
                }

                if (apt.hasOwnProperty("type") && apt.type != null && String(apt.type) != "") {
                    updated.type = apt.type;
                }

                if (apt.hasOwnProperty("plan_image") && apt.plan_image != null && String(apt.plan_image) != "") {
                    updated.plan = apt.plan_image;
                    addImageUrl(String(apt.plan_image));
                }

                if (apt.hasOwnProperty("preview") && apt.preview != null && String(apt.preview) != "") {
                    updated.base_image = apt.preview;
                    addImageUrl(String(apt.preview));
                }

                if (apt.hasOwnProperty("images") && apt.images != null && apt.images is Array && (apt.images as Array).length > 0) {
                    updated.render = apt.images;
                    collectRenderImages(apt.images);
                }

                resultData[num] = updated;

                trace("[CRMLoader] Обновлена квартира " + num);
            }

            collectImagesFromResult();

            trace("[CRMLoader] Обновление завершено. Сохраняю файл...");
            saveData();
            prefetchImages();
        }

        private function saveData():void {
            try {
                var file:File = File.applicationStorageDirectory.resolvePath("crm_data.json");
                var stream:FileStream = new FileStream();
                stream.open(file, FileMode.WRITE);
                stream.writeUTFBytes(JSON.stringify(resultData));
                stream.close();

                trace("[CRMLoader] crm_data.json успешно обновлён!");

                // Сигналим слушателям о завершении обновления данных
                CRMData.reload(); // обновляем статичные данные в памяти
                dispatchEvent(new Event(DATA_UPDATED));

            } catch (e:Error) {
                trace("[CRMLoader] Ошибка записи: " + e.message);
            }
        }

        private function onError(e:IOErrorEvent):void {
            trace("[CRMLoader] Ошибка загрузки: " + e.text);
        }

        private function ObjectKeys(obj:Object):Array {
            var arr:Array = [];
            for (var k:String in obj) arr.push(k);
            return arr;
        }

        private function addImageUrl(url:String):void {
            if (url && url.length > 0) {
                imagesToPrefetch[url] = true;
            }
        }

        private function collectRenderImages(arr:Array):void {
            for each (var raw:* in arr) {
                var url:String = String(raw);
                addImageUrl(url);
            }
        }

        private function collectImagesFromResult():void {
            for each (var apt:Object in resultData) {
                if (!apt) continue;
                if (apt.hasOwnProperty("base_image")) addImageUrl(String(apt.base_image));
                if (apt.hasOwnProperty("plan")) addImageUrl(String(apt.plan));

                if (apt.hasOwnProperty("render")) {
                    var render:* = apt.render;
                    if (render is Array) {
                        collectRenderImages(render as Array);
                    } else if (render is String) {
                        addImageUrl(String(render));
                    }
                }
            }
        }

        private function prefetchImages():void {
            var list:Array = [];
            for (var url:String in imagesToPrefetch) {
                list.push(url);
            }

            if (list.length == 0) {
                trace("[CRMLoader] Нет изображений для предзагрузки.");
                return;
            }

            trace("[CRMLoader] Предзагрузка изображений: " + list.length);
            ImageCache.prefetchUrls(list, function():void {
                trace("[CRMLoader] Предзагрузка изображений завершена.");
            });
        }
    }
}
