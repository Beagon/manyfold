// This file is auto-generated by ./bin/rails stimulus:manifest:update
// Run that command whenever you add a new controller or create them with
// ./bin/rails generate stimulus controllerName

import { application } from './application'

import BulkEditController from './bulk_edit_controller'
import CarouselController from './carousel_controller'
import CocoonedController from './cocooned_controller'
import CopyTextController from './copy_text_controller'
import EditableController from './editable_controller'
import I18nController from './i18n_controller'
import RendererController from './renderer_controller'
import StorageServiceController from './storage_service_controller'
import TagInputController from './tag_input_controller'
import TagSectionController from './tag_section_controller'
import UploadController from './upload_controller'
import ZxcvbnController from './zxcvbn_controller'

application.register('carousel', CarouselController)
application.register('cocooned', CocoonedController)
application.register('copy-text', CopyTextController)
application.register('bulk-edit', BulkEditController)
application.register('editable', EditableController)
application.register('i18n', I18nController)
application.register('renderer', RendererController)
application.register('storage-service', StorageServiceController)
application.register('tag-input', TagInputController)
application.register('tag-section', TagSectionController)
application.register('upload', UploadController)
application.register('zxcvbn', ZxcvbnController)
