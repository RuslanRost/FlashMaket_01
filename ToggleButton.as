package {
    import flash.display.MovieClip;
    import flash.events.MouseEvent;
    import flash.events.Event;

    public class ToggleButton extends MovieClip {
        public var state:Boolean = false;

        public static const TOGGLE_CHANGED:String = "ToggleChanged";

        private var _enabled:Boolean = true; // активна ли кнопка

        public function ToggleButton() {
            super();

            stop(); // кадры ещЄ не готовы Ч просто стопаем

            this.buttonMode = true;
            this.mouseChildren = false;

            this.addEventListener(MouseEvent.CLICK, onClick);

            // ¬ј∆Ќќ: ждем, пока кнопка окажетс€ на сцене
            this.addEventListener(Event.ADDED_TO_STAGE, onAdded);

        }

        private function onAdded(e:Event):void {
            this.removeEventListener(Event.ADDED_TO_STAGE, onAdded);
            //updateVisualState();
        }

        private function onClick(e:MouseEvent):void {
            if (!_enabled) {
                return;
            }

            state = !state;

            updateVisualState();
            dispatchEvent(new Event(TOGGLE_CHANGED));
        }

        private function updateVisualState():void {
            if (state) {
                gotoAndStop(2);
            } else {
                gotoAndStop(1);
            }
        }

        public function setState(value:Boolean):void {
			if (state != value){
				state = value;
				updateVisualState();
			}
        }

        public function getState():Boolean {
            return state;
        }

        public function setEnabled(value:Boolean):void {
            _enabled = value;
        }

        public function getEnabled():Boolean {
            return _enabled;
        }
    }
}
