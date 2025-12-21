package {
    import flash.display.MovieClip;
    import flash.display.Sprite;
    import flash.display.SimpleButton;
    import flash.events.MouseEvent;
    import flash.events.Event;
    import flash.events.TransformGestureEvent;
    import flash.text.TextField;
    import flash.text.AntiAliasType;
    import flash.text.GridFitType;
    import flash.display.Bitmap;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.ui.Multitouch;
    import flash.ui.MultitouchInputMode;
    import PhotoPopup;
    import PhotoPopup_01;
    import PlanPopup;
    import PlanPopup_01;

    public class ApartmentPopup extends MovieClip {
        public static const CLOSED:String = "ApartmentPopupClosed";
        public var tfNumber:TextField;
        public var tfType:TextField;
        public var tfStatus:TextField;
        public var tfSquare:TextField;
        public var tfArea:TextField;
        public var tfBigText:TextField;

        public var brdr_Image:MovieClip;
        public var btn_ClosePopup:SimpleButton;
        public var btn_Photo:SimpleButton;
        public var btn_Plan:SimpleButton;

        private var currentBitmap:Bitmap;
        private var currentApartmentNumber:String = "";
        private var darkBg:Sprite;
        private var photoPopup:PhotoPopup;
        private var planPopup:PlanPopup;
        private var baseBitmapScaleX:Number = 1;
        private var baseBitmapScaleY:Number = 1;
        private var popupBaseScaleX:Number = 1;
        private var popupBaseScaleY:Number = 1;
        private var zoomFactor:Number = 1;
        private var targetScaleX:Number = 1;
        private var targetScaleY:Number = 1;
        private var targetX:Number = 0;
        private var targetY:Number = 0;
        private var rightDrag:Boolean = false;
        private var lastDragPoint:Point = null;
        private const MIN_ZOOM:Number = 1;
        private const MAX_ZOOM:Number = 3;

        public function ApartmentPopup() {
            super();
            addEventListener(Event.ADDED_TO_STAGE, onAdded);
            addEventListener(Event.REMOVED_FROM_STAGE, onRemoved);
            Multitouch.inputMode = MultitouchInputMode.GESTURE;
        }

        private function onAdded(e:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAdded);

            darkBg = new Sprite();
            darkBg.graphics.beginFill(0x000000, 0.5);
            darkBg.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
            darkBg.graphics.endFill();
            darkBg.addEventListener(MouseEvent.CLICK, onBackgroundClick);
            darkBg.addEventListener(MouseEvent.MOUSE_WHEEL, absorbEvent, false, 1, true);
            darkBg.addEventListener(TransformGestureEvent.GESTURE_ZOOM, absorbEvent, false, 1, true);

            if (parent) parent.addChildAt(darkBg, parent.getChildIndex(this));

            if (btn_ClosePopup) {
                btn_ClosePopup.addEventListener(MouseEvent.CLICK, onCloseClick);
            }
            if (btn_Photo) {
                btn_Photo.addEventListener(MouseEvent.CLICK, onPhotoClick);
            }
            if (btn_Plan) {
                btn_Plan.addEventListener(MouseEvent.CLICK, onPlanClick);
            }

            configureTextFields();
            setupInteractionListeners();
            addEventListener(Event.ENTER_FRAME, onNextFrame);
            addEventListener(Event.ENTER_FRAME, onSmoothUpdate);
        }

        private function setupInteractionListeners():void {
            if (stage) {
                stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel, false, 0, true);
                stage.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightDown, false, 0, true);
                stage.addEventListener(MouseEvent.RIGHT_MOUSE_UP, onRightUp, false, 0, true);
                stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveDrag, false, 0, true);
            }
            if (brdr_Image) {
                brdr_Image.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel, false, 0, true);
                brdr_Image.addEventListener(TransformGestureEvent.GESTURE_ZOOM, onGestureZoom, false, 0, true);
                brdr_Image.addEventListener(TransformGestureEvent.GESTURE_PAN, onGesturePan, false, 0, true);
            }
        }

        private function removeInteractionListeners():void {
            if (stage) {
                stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
                stage.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightDown);
                stage.removeEventListener(MouseEvent.RIGHT_MOUSE_UP, onRightUp);
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveDrag);
            }
            if (brdr_Image) {
                brdr_Image.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
                brdr_Image.removeEventListener(TransformGestureEvent.GESTURE_ZOOM, onGestureZoom);
                brdr_Image.removeEventListener(TransformGestureEvent.GESTURE_PAN, onGesturePan);
            }
            if (btn_Photo) {
                btn_Photo.removeEventListener(MouseEvent.CLICK, onPhotoClick);
            }
            if (btn_Plan) {
                btn_Plan.removeEventListener(MouseEvent.CLICK, onPlanClick);
            }
        }

        private function onNextFrame(e:Event):void {
            removeEventListener(Event.ENTER_FRAME, onNextFrame);

            this.x = (stage.stageWidth  - this.width)  * 0.5;
            this.y = (stage.stageHeight - this.height) * 0.5 + 300;
            popupBaseScaleX = this.scaleX;
            popupBaseScaleY = this.scaleY;
            zoomFactor = 1;
            targetScaleX = this.scaleX;
            targetScaleY = this.scaleY;
            targetX = this.x;
            targetY = this.y;
        }

        private function onBackgroundClick(e:MouseEvent):void {
            closePopup();
        }

        private function onCloseClick(e:MouseEvent):void {
            closePopup();
        }

        private function onRemoved(e:Event):void {
            removeInteractionListeners();
            removeEventListener(Event.ENTER_FRAME, onSmoothUpdate);
        }

        private function closePopup():void {
            // Сообщаем подписчикам, что попап закрывается (bubbles=true для ловли на сцене)
            dispatchEvent(new Event(CLOSED, true));
            removeInteractionListeners();
            if (darkBg && darkBg.parent) darkBg.parent.removeChild(darkBg);
            if (parent) parent.removeChild(this);
        }

        public function getCurrentApartmentNumber():String {
            return currentApartmentNumber;
        }

        private function loadImage(url:String):void {
            if (!brdr_Image) return;
            if (!url || url.length == 0) return;

            var requestedFor:String = currentApartmentNumber;

            ImageCache.getBitmap(url, function(bmp:Bitmap):void {
                // ignore if meanwhile открыли другую квартиру
                if (requestedFor != currentApartmentNumber) return;
                if (!bmp || !bmp.bitmapData) return;

                renderBitmap(bmp);
            }, function(err:String):void {
                trace("[ApartmentPopup] Ошибка загрузки изображения:", err);
            });
        }

        private function renderBitmap(bmp:Bitmap):void {
            if (!brdr_Image || !bmp) return;

            bmp.smoothing = true;

            var origW:Number = bmp.bitmapData.width;
            var origH:Number = bmp.bitmapData.height;

            var bounds:Object = brdr_Image.getBounds(brdr_Image);
            var frameW:Number = bounds.width;
            var frameH:Number = bounds.height;

            while (brdr_Image.numChildren > 0) {
                brdr_Image.removeChildAt(0);
            }

            currentBitmap = bmp;
            brdr_Image.addChild(bmp);

            bmp.scaleX = frameW / origW;
            bmp.scaleY = frameH / origH;

            bmp.x = bounds.x * -1;
            bmp.y = bounds.y * -1;

            baseBitmapScaleX = bmp.scaleX;
            baseBitmapScaleY = bmp.scaleY;
        }

        public function showApartmentInfo(apartmentNumber:String):void {
            currentApartmentNumber = apartmentNumber;

            var type:String     = CRMData.getDataById(apartmentNumber, "type");
            var status:String   = CRMData.getDataById(apartmentNumber, "status");
            var square:*        = CRMData.getDataById(apartmentNumber, "square");
            var imageUrl:String = CRMData.getDataById(apartmentNumber, "base_image");

            // --- Перевод статуса ---
            var statusMap:Object = {
                "Available":        "Доступно",
                "Reserved":         "Забронировано",
                "Occupied":         "Куплено",
                "Сlosed for sale":  "Закрыто к продаже"
            };

            var statusRu:String = statusMap.hasOwnProperty(status) ? statusMap[status] : status;

            // площадь
            var sqNum:Number = Number(square);
            var sqText:String = Math.round(sqNum).toString() + " м²";

            // вывод
            tfType.text   = type ? type : "";
            tfStatus.text = statusRu;
            tfArea.text   = sqText;
            if (tfBigText) {
                tfBigText.text = getTypeDescription(type);
            }

            if (imageUrl) loadImage(imageUrl);
        }

        private function onMouseWheel(e:MouseEvent):void {
            if (!hitTestPoint(e.stageX, e.stageY, true)) return;
            var factor:Number = (e.delta > 0) ? 1.1 : 0.9;
            e.stopImmediatePropagation();
            applyZoom(factor, e.stageX, e.stageY);
        }

        private function onGestureZoom(e:TransformGestureEvent):void {
            if (!hitTestPoint(e.stageX, e.stageY, true)) return;
            e.stopImmediatePropagation();
            applyZoom(e.scaleX, e.stageX, e.stageY);
        }

        private function onGesturePan(e:TransformGestureEvent):void {
            if (!hitTestPoint(e.stageX, e.stageY, true)) return;
            e.stopImmediatePropagation();
            targetX += e.offsetX;
            targetY += e.offsetY;
        }

        private function applyZoom(factor:Number, stageX:Number, stageY:Number):void {
            if (!parent) return;

            var oldZoom:Number = zoomFactor;
            var newZoom:Number = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, zoomFactor * factor));
            var applied:Number = newZoom / oldZoom;
            if (applied == 1) return;

            zoomFactor = newZoom;

            var globalPoint:Point = new Point(stageX, stageY);
            var localPointBefore:Point = this.globalToLocal(globalPoint);

            targetScaleX = popupBaseScaleX * zoomFactor;
            targetScaleY = popupBaseScaleY * zoomFactor;

            var globalPointAfter:Point = localToGlobalWithScale(localPointBefore, targetScaleX, targetScaleY);
            var dx:Number = globalPoint.x - globalPointAfter.x;
            var dy:Number = globalPoint.y - globalPointAfter.y;

            targetX += dx;
            targetY += dy;
        }

        private function absorbEvent(e:Event):void {
            e.stopImmediatePropagation();
        }

        private function configureTextFields():void {
            applyTextSettings(tfNumber);
            applyTextSettings(tfType);
            applyTextSettings(tfStatus);
            applyTextSettings(tfSquare);
            applyTextSettings(tfArea);
            applyTextSettings(tfBigText);
        }

        private function applyTextSettings(tf:TextField):void {
            if (!tf) return;
            tf.antiAliasType = AntiAliasType.ADVANCED;
            tf.gridFitType = GridFitType.SUBPIXEL;
            tf.cacheAsBitmap = true;
        }

        private function onRightDown(e:MouseEvent):void {
            // RIGHT_MOUSE_DOWN сюда уже приходит, отдельная проверка buttonIndex не нужна
            rightDrag = true;
            lastDragPoint = new Point(e.stageX, e.stageY);
            e.stopImmediatePropagation();
        }

        private function onRightUp(e:MouseEvent):void {
            rightDrag = false;
            lastDragPoint = null;
        }

        private function onMouseMoveDrag(e:MouseEvent):void {
            if (!rightDrag || !lastDragPoint) return;
            var dx:Number = e.stageX - lastDragPoint.x;
            var dy:Number = e.stageY - lastDragPoint.y;
            if (dx == 0 && dy == 0) return;
            targetX += dx;
            targetY += dy;
            lastDragPoint.x = e.stageX;
            lastDragPoint.y = e.stageY;
            e.stopImmediatePropagation();
        }

        private function localToGlobalWithScale(local:Point, sx:Number, sy:Number):Point {
            return new Point(this.x + local.x * sx, this.y + local.y * sy);
        }

        private function onSmoothUpdate(e:Event):void {
            var ease:Number = 0.4;
            this.scaleX += (targetScaleX - this.scaleX) * ease;
            this.scaleY += (targetScaleY - this.scaleY) * ease;
            this.x += (targetX - this.x) * ease;
            this.y += (targetY - this.y) * ease;
        }

        private function onPhotoClick(e:MouseEvent):void {
            e.stopImmediatePropagation();
            if (!stage) return;
            if (!photoPopup) {
                try {
                    photoPopup = new PhotoPopup_01();
                } catch (err:Error) {
                    photoPopup = new PhotoPopup();
                }
            }
            if (!photoPopup.stage) {
                stage.addChild(photoPopup);
            }
            photoPopup.showForApartment(currentApartmentNumber);
        }

        private function onPlanClick(e:MouseEvent):void {
            e.stopImmediatePropagation();
            if (!stage) return;
            if (!planPopup) {
                try {
                    planPopup = new PlanPopup_01();
                } catch (err:Error) {
                    planPopup = new PlanPopup();
                }
            }
            if (!planPopup.stage) {
                stage.addChild(planPopup);
            }
            planPopup.showForApartment(currentApartmentNumber);
        }

        private function getTypeDescription(type:String):String {
            var desc:Object = {
                "Extency Superior": "Эргономичное пространство резиденции Extency Superior создано с особым вниманием к деталям, где каждая составляющая работает над созданием атмосферы максимального комфорта. Благодаря такому подходу, премиальная резиденция Extency Superior превращается в настоящий оазис спокойствия, где каждая минута отдыха приносит удовольствие, все потребности предугаданы, качество сервиса соответствует высоким стандартам, атмосфера располагает к полноценному отдыху и восстановлению сил. Результатом такого внимания к каждой составляющей становится достижение безупречного баланса между эстетикой и функциональностью.",
                "Emerald": "Премиальная резиденция категории Emerald — это воплощение роскошного комфорта, где каждая деталь тщательно продумана и гармонично сочетается с остальными элементами пространства, уникальность которого определяется изысканным интерьером с тщательно подобранными элементами декора, профессиональной организацией многоуровневого освещения, эргономичной мебелью премиум-класса, продуманным зонированием. Резиденция Emerald представляет собой идеальное воплощение концепции, где дизайн служит не только украшением, но и функциональным решением, пространство организовано, предугадывая потребности, материалы отличаются исключительным качеством, комфорт становится неотъемлемой частью каждой детали. Такое гармоничное сочетание всех компонентов превращает резиденцию в уникальное пространство, где ощущается особенность и окружение заботой.",
                "Family": "Величественная резиденция категории Family раскрывается как изысканная симфония пространства и света. Каждое мгновение, проведенное здесь, наполнено особым очарованием и комфортом. Пространство дышит гармонией: воздушные перспективы открываются через панорамные окна, играя бликами на полированных поверхностях, благородные материалы создают атмосферу утонченной роскоши, плавные линии интерьера сливаются в единый художественный образ, а естественный свет творит волшебство, преображая пространство в течение дня. Резиденция категории Family — настоящая поэма комфорта, где тихие уголки манят уединением, светлые залы приглашают к отдыху, воздушная легкость наполняет каждый сантиметр, изысканная простота создает атмосферу благородства. Подобно произведению искусства, резиденция раскрывает свою красоту постепенно, даря незабываемые впечатления и погружая в мир утонченного комфорта и элегантности. Здесь время течет по-особенному, позволяя насладиться каждым мгновением пребывания в этом удивительном пространстве.",
                "Penthouse": "Императорская резиденция категории Penthouse предстает перед взором как величественный дворец современного искусства, где каждая деталь пронизана духом изысканной роскоши и утонченного вкуса. Божественная гармония пространства раскрывается в симфонии бескрайних видов, растворяющихся в лазурной дали, благородных текстур, мерцающих подобно звездам, изящных изгибов, сплетающихся в неповторимый узор, танцующих лучей, создающих волшебную игру теней. Каждое мгновение в резиденции становится путешествием в мир, где каждая деталь продумана до мелочей, где красота сливается с функциональностью, где царит атмосфера приватности, где роскошь становится естественной."
            };
            return desc.hasOwnProperty(type) ? desc[type] : "";
        }
    }
}
